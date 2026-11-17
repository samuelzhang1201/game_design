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
per-frame gear clearance, sole grounding, authored STANDBY / DEFEND loops). Body maps:
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
  (`*_retarget`, `*_raw`, `WALK_base`, `STANDBY_src`, `ATTACK_swordcut`) never are;
- it returns the MARCH measure for `army_art.csv`: `stride_m` 1.618, `steps` 0.34;0.83 (35
  intervals), and the rest height 1.636 m, 8,604 tris.

MARCH contact lock (`LOCK`, `_lock_feet`): in the retargeted in-place walk a planted sole did not
travel back at one speed and the right toe dragged forward through its push-off (a 48 mm
planted-sole slide; the certifier's bound is 23.2 mm). A foot is planted while its lowest point is
within 4 mm of its lowest in the clip AND its deepest sole points travel back at least half the
walk's median planted speed (0.0466 m a frame); then those points are made to travel straight back
at that speed, the foot moved by the accumulated difference (orientation kept), thigh and shin
following by two-bone IK in their own bend plane; the offset eases to zero through the swing
(largest 14 / 19 mm, left / right). A pinned point past the leg's reach is pulled back to it with
the knee bent at least `min_knee_deg` 2° (largest pull-back 2.9 mm, left mid-stance): clamping
the knee straight instead left the foot 3 mm off the shin and the leg on its singular pose, where
the pivot helper's native endpoint check fails on float rounding. In the first half of each swing the foot is lifted until its
lowest point clears 5 mm (eased over 3 frames; largest 7 mm). Native MARCH's worst planted slide is
then 11.9 mm at the constant stride, so no `phase_map` is needed.

Polish (`POLISH`, owner 2026-11-17, the first install's critic notes; each knob bracketed in
real-window and map shots, two critic rounds; overridable with the `INFANTRY_POLISH` environment
variable as JSON):

- rest: STANDBY's relaxed body takes GARRISON's left arm (shoulder to the shield socket, same
  phase), pinned at STANDBY's own shoulder and turned `rest_arm_turn` 0.8 of the way from the
  guard's twisted chest to the figure's own facing (copied on the chest alone the shield stood
  edge-on at the side: the guard leads with the shield shoulder); then the wrist turns until the
  shield's outer face (the disc's least axis, from the mesh) looks at least `rest_shield_up_deg`
  30° above level (up to 34°): upright, the face caught no light from the map's camera. Turning
  about the handle instead swings the face sideways (the handle is upright in this carry);
- shield wood: planks and rim drawn to `shield_contrast` 0.55 of their spread about the mean
  colour (a light ochre plank stood out), then
  `shield_tone` (1.25, 0.95) (saturation, value shares): the knight's (0.55, 0.8) left the raised
  shields near-black discs on the map, (0.9, 1.2) chalky discs brighter than the banner;
- shield hand: in every clip the thumb chain turns about its base until its tip rests at
  `thumb_tip` in the hand's frame (over the curled index), up to 38°: the retargeted grip laid
  the thumb along the handle (the guard's own grip too, so copying its fist changed nothing);
- MARCH blade: the right wrist turns until the blade leans out of the body's mid-plane by at least
  `blade_min_deg` 30° (up to 26°): it passed close to the knee. A floor on its forward pitch laid
  it along the front shin, one measured in the side-to-vertical plane tipped it onto the front shoe;
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

Parameters measured on this MARCH: entry = exit 13/14 (the passing frame: the right sole flat,
the left boot 2 cm up just after toe-off, thighs 5.9° apart — the same frame of the walk the
knight's 25/28 was); NEUTRAL 181/420 (thighs 0.6° apart, the left sole planted); FOOT left
168/420, right 387/420 (flattest planted sole, spread 6.1 / 3.5 mm). Bounds R-A at k 25.8437
world m per model m: contact 23217 µm, seam 1935 µm. Audit: skin flags introduced 0, penetration
557 µm, hover / slide / seam 1 µm on both turns. Stop, start and hold are admitted at MARCH 13/14
only.

Then `tools/units3d/certify_locomotion.py` re-issues the infantry and artillery certificates
(`docs/reviews/cluster-formations/evidence/locomotion/{infantry,artillery}/`) and their rows in
`data/army/unit_locomotion.csv`, `body_locomotion_*_contact_um` in `data/army/balance.csv`.
