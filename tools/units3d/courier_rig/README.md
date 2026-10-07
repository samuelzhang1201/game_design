# The courier re-rigged and re-animated (the cavalry's method)

Owner 2026-10-07: 请根据最新骑兵动作建模流程，重新设计信使的动作 — on the **existing game mesh** (the herald on
the white horse, `courier_build.py`'s output), asked and answered: a **four-beat gallop** and **GALLOP + IDLE**
only (the game plays no other). Run in the owner's open Blender through the MCP; the royal rig's helpers are
exec'd first (`cavalry_rig/weights` for the welded solve) and this folder points them at the courier:

```python
G = {}
for f in ("royal_rig/common", "royal_rig/labels", "royal_rig/weights", "royal_rig/validate", "royal_rig/actions",
          "cavalry_rig/weights", "courier_rig/common", "courier_rig/armature", "courier_rig/weights",
          "courier_rig/actions", "courier_rig/export"):
    G["__file__"] = ".../tools/units3d/%s.py" % f; exec(open(G["__file__"]).read(), G)
G["load"](); G["relax_hems"](); G["build"](); G["courier_weights"](); G["all_clips"](); G["export"]()
```

then `python3 tools/units3d/courier_rig/install.py` and Godot's import. `courier_build.py` stays the MODEL's
build (Tripo fit, cull, reduce, bake); re-running it re-exports the old rig over `courier.glb` — run this folder
after it.

## Files (`assets/3D/units/courier/model_wip/`, git-ignored)

| file | what it is |
| --- | --- |
| `tripo/courier_rigged_tripo.blend` | `courier_build.py`'s file: the game mesh `courier` (every vertex carries `part_id`), the source of `load` |
| `tripo/textured.glb`, `parts.glb` | the owner's Tripo generation (kept for a model rebuild) |
| `rig/courier_rig_work.blend` | the scene `Courier_Rig`: the mesh, `courier_rig` (57 bones), the actions `courier_GALLOP`, `courier_IDLE` |
| `rig/courier_rigged.glb` | `export.py`'s export: 19,346 tris, one skin, 57 joints, the two clips at 30 fps |
| `rig/shots/` | `gate3_*.png`, `lab_*` (labels), `w_*` (weights), `gallop_*_sheet.png`, `idle_*sheet.png`, `rump*` (junctions), `gif/<CLIP>.gif` |

## Phases

| phase | where | what |
| --- | --- | --- |
| 1 | `common.load` | the game mesh appended, its old skin dropped, turned half round: faces −Y, left +X; `part_id` → `part` |
| 1d | `weights.courier_roles` | roles from the parts (`courier/tripo_parts.csv`); the near rein is welded into the bridle part and is found by its distance from the head; the coat split into sleeves / torso / skirt by a sleeve's reach AND being outside the coat's sides or before its front (a plain distance competition took the side panels for sleeves) |
| 2–3C | `armature.py` | 5 cm slices of each leg's own part, a leg-coloured gridded x-ray side render; the cavalry's bone set with five tail bones + `Pole`, `Pennon1/2`, `Case`, `Reins.L`, `Reins.R` (one rein runs to each hand) |
| 4 | `weights.courier_weights` | the horse heat-solved WELDED (6 mm), the skill's 4e limits (leg reach + fade to the torso, belly off the lower legs, tail bones only on the tail, no leg bone on the neck); saddle tack rigid on Spine1 with a 4-ring blend; breast collar and bridle copy the skin under them; the rider heat-solved per sub-group, only the forearms' contacts cut (sleeve and coat are one cloth at the shoulder); head, hands, hat, staff, case rigid; the pennant graded down its fly; each rein graded bit → its own hand |
| 4f | `common.relax_hems` | the rump shell's off-side hem is a saw-toothed open edge the generator left over the off hind leg; its free boundary is relaxed (5 passes, ≤ 25 mm a vertex there, ≤ 12 mm on the near side, where more opened holes in the flank) |
| 5 | `weights.courier_numeric`, royal `validate.py` | gates all 0; stretch ≤ 15 edges over the test poses (head down: the reins, which must stretch) |
| clips | `actions.py` | below |
| 6/7 | `export.py` | one NLA track a clip, the debug colour layers dropped |

## The clips (blender-natural-animation, 30 fps, loops, in place)

| clip | frames | what |
| --- | --- | --- |
| GALLOP | 14 | the right-lead transverse gallop — LH 0, RH .10, LF .38, RF .50, suspension — duty .29, 2.8 m a loop; every hoof on a periodic PCHIP path (the skill's canter recipe), every leg SOLVED per frame by a deterministic hinge least squares with a small abduction of its first bone (no Blender IK; the legs slant inward, so a planar leg slid its hoof sideways), preferences measured against a standing leg (the mesh walks: the near fore is raised at rest); body pitch / lift / back flex on the footfalls, the neck 2 f late, the tail streaming back and DOWN (it must hide the rump's hem); the rider SIMULATED, not posed (owner 2026-10-07: 上半身过于僵硬): damped springs hung from the saddle and driven by the footfalls' impacts (`rider_springs`, run to steady state, the last loop kept) — his back rounded (`BACK_ARCH` 12°, owner: 他的背弓起来一点 — the pelvis tucked, the lower and upper back rolled forward, the shoulders rounded: a curve, not a fold at the hips), his pelvis takes only a little of the saddle's pitch, his trunk swings on it ~10°, his chest follows ~2 f late, an impact-driven give runs up spine → chest → neck a frame a link, his hips sink on each landing, his head is pulled back to a level gaze (its world travel 54 / 70 mm against 139 / 87 posed; the trunk's timing a grid search for the stillest head, `head_still`), a little roll and twist from the right lead; feet kept in the irons, rein hand following the horse's nod, the staff raked forward so the pennant flies clear of his hat (upright, the far view merged flag and hat into one blob), the pennant streaming, the case bouncing 2 f behind |
| IDLE | 150 | halted square; breathing, a slow sway, the near hind cocked on its toe for a while, a nod, one swish; the rider looks left, then right, leans to his left and pats the dispatch case twice with his head up (a bow read as dozing at map size), takes up the rein again |

An independent critic compared it with the old clips in the engine (2026-10-07): the new gallop reads as one
(reach, gathering, suspension) where the old shuffled like a trot, and the halted horse now stands square;
its should-fix notes (the staff, the rider's lean, the bow at the case) were fixed.

Gates (`actions.gait_metrics`): footfalls in the gallop's order (LH 13.75 → RH 1.25 → LF 5.5 → RF 6.75 of 14);
planted slide ≤ 0.1 mm a frame against the ground's 0.2 m (IDLE ≤ 0.5 mm); penetration ≤ 0.3 mm; loops close
exactly; the largest frame-to-frame jump above its neighbours 26° (the fore hoof's flick at lift-off, a real
and continuous motion at 14 frames a stride), ≤ 16° elsewhere; stretch over the clips only in the pennant
(the cloth streaming) and, in IDLE's reach, the coat's armpit and the left rein.

## Not done / known

* Where the off hind leg was cut in under the rump shell, the shell's inside edges and a small notch show
  between the legs from level with or BELOW the belly at the gallop's extremes (the game's camera looks
  down at 22–55°; not seen on the map).
* The left rein stretches when the hand goes to the case (a strap between two moving anchors).
* The flag is a hanging pennant the clips swing back; its cloth stretches as it streams.
