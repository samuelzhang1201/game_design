# Cavalry MARCH re-author (LOCO-CAV-MARCH, 2026-11-13)

Owner ruling (via the coordinating session, 2026-11-13): "Re-author cavalry MARCH". This is an explicit
exception to the protected-source-clip rule, for cavalry MARCH only (`owner-rulings-2026-11-10.md` R-I).
The bound stays contact 29,273 µm (0.60 world m, k = 20.4973). Every other clip, the mesh, skin, binds,
rest, root, seat and scale are unchanged.

## What was wrong

No phase map could bring the shipped MARCH under the per-vertex slide bound (LOCO-CERT-CAV findings:
the best possible map floors at about 29 mm sampled, about 41.6 mm with the sampling margin). Two causes,
both in how the clip was keyed, not in the canter it was keyed from:

1. **Sixteen keys a loop.** The generator (`tools/units3d/cavalry_rig/actions.py`, `op_gait`) puts each
   fetlock exactly on a straight stance path at every key. A 3- or 4-bone leg keyed at the two ends of a
   0.15 m step leaves that path between them once each bone's rotation is interpolated. Measured on
   the shipped capture at the canter's true 2.4 m loop: 10.8 mm of slide at the keys alone, 92.9 mm over
   all samples. The old `stride_m` 2.327 and LOCO-CAV-PHASE's phase map were compensating for that
   in-between error, which differs from hoof to hoof, so no single pace could fit all four.
2. **The swing start.** `op_gait`'s smoothstep swing begins at rest in the model frame. While the hoof is
   still inside the 0.5 mm planting band, it is suddenly carried forward at the body's speed over the
   ground. Also, `op_aim` turned the hoof by the least rotation from wherever the leg left it, so a planted
   hoof rolled 3–4° about its own axis.

## What changed

Everything was made in the owner's Blender, on a copy of `cavalry_rig_work.blend`
(`assets/3D/units/cavalry/model_wip/march_reauthor_20261113/`, git-ignored). Before any change, the
generator re-run at 16 keys reproduced the shipped MARCH exactly (max matrix difference 0.0).
`tools/units3d/cavalry_rig/march_reauthor.py` then re-keyed MARCH only:

- **128 keys** over the same 0.5333 s (240 fps). Every other bone is the same function of the phase.
- **A rigid planted hoof.** The hoof is the least rotation from its rest frame onto the generator's own aim
  direction (`op_hoof`). In Blender, all four planted hooves hold 0.0 mm and 0.0° at every key.
- **A Hermite swing** (`swing`). Its end slopes equal the stance's travel, so the hoof leaves and meets the
  ground at zero ground speed. It follows through about 10 cm behind after lift-off and reaches about
  10 cm ahead before it lands. The hoof's fold keeps the generator's own timing (sin): easing it in as sin²
  scored worse (14.8 mm) and, per the critic, left a lifting fore hoof dangling toe-down.
- **The import** `cavalry.glb.import` `animation/fps` went from 30 to 240. Godot's importer re-bakes every
  clip at that rate, and at 30 it resampled the 128 keys back to 16. The other clips' LINEAR samplers are
  on the 1/30 s grid and their STEP samplers are all constant, so baking them at 240 changes no pose
  (the pivots are rebuilt from exact keys by `pivot_import.gd` anyway). A GUT test holds MARCH's key
  count.
- `tools/units3d/cavalry_rig/march_transplant.py` moved ONLY the MARCH channels into the shipped
  `assets/3D/units/cavalry/cavalry.glb`:
  - it appended 159 new output accessors and one shared 129-key input, and repointed MARCH's samplers;
  - every original JSON table and BIN byte is kept, as are the other clips (the appended pivots included);
  - re-running it on the pre-transplant GLB with the same export reproduces the bytes (on an already
    transplanted GLB it would append a second set);
  - the old MARCH accessors stay in the BIN, unused.
- `army_art.csv` cavalry: `stride_m` is now 2.4 (the canter's own loop, `actions.py` `STRIDE`) and
  `phase_map` is empty. The re-authored clip needs no map, so cavalry is paced like every other arm.

- `tools/units3d/check_cavalry_march_capture.py` is left byte-identical (the relative-skin bound pins its
  digest). Its `FROZEN` GLB digest names the 16-key MARCH installed before this step, so it now refuses
  the installed GLB by design: it is the historical custody check of the old clip.

## Godot-native measurement

`march-native-measure.json` is the certifier's own output (`march-native-measure.config.json`, held at
the provider's admitted MARCH phase 7/16). It is **not a certificate**: the native PIVOT clips are
180° source fixtures that no MARCH pose meets, so the pivots and their seams fail here. LOCO-CAV-PROVIDER
(#314) replaces them, and LOCO-CERT-CAV certifies the two together.

| Quantity, MARCH | Shipped (stride 2.327 + phase map) | Re-authored (stride 2.4) |
|---|---:|---:|
| Per-vertex slide | 90,653 µm (79,689 at a constant 2.327) | **10,902 µm** (7,468 + 3,434 margin) |
| Loop seam | 1 µm | 1 µm |
| Bounds | contact 29,273, seam 2,440 | same |

Over the whole run:

| Quantity | Re-authored |
|---|---|
| Penetration | 7,693 µm (pass) |
| Hover | 3,599 µm (pass) |
| Envelope | 738 ≤ 804 sim m |
| Skin flags introduced | 0 |
| Stance | complete |

**The planting band** is inherited from the native MARCH, which is now this clip. All four feet keep the
0.5 mm floor: every hoof's stance sole still sits a few millimetres under the seated plane, as before.

## Real-window review

`tools/units3d/march_gait_review.gd` (a real Godot window, `cavalry.tscn` paced by the real
`Map3DUnitRig.keep_pace` over a striped ground, fixed side camera, red post at the hind-left touchdown):
- before: `--variant map` on main before this PR (its `phase_map` is now empty);
- after: `--variant stride --stride 2.4`.

Worst hoof bone drift per stance (model m), as the tool prints it:

| Hoof | Before | After |
|---|---:|---:|
| HindHoof.L | 0.0105 | 0.0005 |
| HindHoof.R | 0.0181 | 0.0001 |
| FrontHoof.L | 0.0170 | 0.0013 |
| FrontHoof.R | 0.0114 | 0.0019 |

The sheets:
- `cycle-before.png` / `cycle-after.png`: the whole loop;
- `hoof-before-after.png`: the planted hind hoof at the post, 2× crop;
- `full-before-after.png`: one whole frame each.
- `fold-sin2-vs-sin.png`: frame 2, the fold eased in as sin² (left, rejected) against the generator's sin
  (right, shipped).

An independent critic, given only the sheets, `taste.md` and the rubric, judged the following over two passes:
- the re-authored loop reads as a canter: the forelegs take turns, where before both tucked high and
  flung forward;
- the planted hoof holds its post from frame 0 to frame 8;
- the sin² fold's toe-down dangle is gone in the shipped variant;
- no new defect, and no change on the rubric's still-image axes.

It still notes these shapes, all the generator's own and unchanged here (the stance aim and the canter's
timing):
- the planted hind is heel-first at touchdown, toe up;
- the forelegs cross at frame 6;
- a fore hoof is mildly toe-down before landing.

It could not judge timing, the loop seam (measured: 1 µm) or how the motion reads at the game's
playing zoom. No in-map march shot was taken here.
