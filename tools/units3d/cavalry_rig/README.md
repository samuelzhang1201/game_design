# The cavalry re-rigged and re-animated (the king's method)

Owner 2026-10-06: 请使用 royal_rig_work 类似的方法，重新设计 cavalry 骑兵的动作 — on the **existing game
mesh** (the 19k-tri knight with the hand-built lance and back shield, `cavalry_tripo_work.blend`), the
**five lance clips**. Run in the owner's open Blender through the MCP; the royal rig's helpers are exec'd
first and this folder points them at the cavalry:

```python
G = {}
for f in ("royal_rig/common", "royal_rig/labels", "royal_rig/weights", "royal_rig/validate", "royal_rig/actions",
          "cavalry_rig/common", "cavalry_rig/armature", "cavalry_rig/weights", "cavalry_rig/actions"):
    G["__file__"] = ".../tools/units3d/%s.py" % f; exec(open(G["__file__"]).read(), G)
G["rig"] = lambda: bpy.data.objects["cavalry_rig"]
G["load"](); G["build"](); G["cav_weights"](); G["all_clips"]()
```

## Files (`assets/3D/units/cavalry/model_wip/rig/`, git-ignored)

| file | what it is |
| --- | --- |
| `cavalry_rig_work.blend` | the scene `Cavalry_Rig`: the mesh, `cavalry_rig` (53 bones), the five actions `cavalry_*` |
| `cavalry_rigged.glb` | the export: 19,047 tris, one skin, 53 joints, the five clips at 30 fps |
| `shots/` | `gate3_*.png`, `poses.png`, `cavalry_clips_overview.png`, `gif/<CLIP>.gif` |

## Phases

| phase | where | what |
| --- | --- | --- |
| 1 | `common.load` | the game mesh appended, its old skin dropped, turned half round: faces −Y, left +X |
| 1d | `weights.cav_roles` | labels are the vertices' own `tripo_part`; roles from `cavalry_tripo/tripo_parts.csv` |
| 2–3C | `armature.py` | leg slices per leg part, gridded x-ray renders, plate junctions; the king's bone set + `Lance`, `Shield`, `Reins` |
| 4 | `weights.cav_weights` | the horse heat-solved WELDED (6 mm) into one surface, the barrel off the leg bones; tack rigid with a 4-ring blend; each rider plate rigid on the nearest bone its rule allows; reins bit → `Reins` |
| 5 | royal `validate.py` | gates all 0; stretch ≤ 2 edges over the test poses |
| clips | `actions.py` | see below |

## The clips (blender-natural-animation)

| clip | frames | what |
| --- | --- | --- |
| MARCH | 16, loop | the king's right-lead 3-beat canter (LH; RH + LF; RF; suspension), duty 0.31, 2.4 m a loop; every hoof's fetlock on a generated path by IK (forelegs 4 bones: the scapula swings) — **0 mm slide, 0 penetration**; the rider 2 f behind the saddle, the neck and tail phase-offset down the chain; the lance upright |
| GARRISON | 120, loop | halted, idling; the shield on the left arm before him, the lance couched level across the neck |
| ATTACK | 75 | gather and couch, two strides easing in and out, the thrust at 34 (he leans in), brake, settle; shield on his back |
| DEFEND | 80 | the horse rears; the shield thrown up over his head, the blow at 32, the lance held up and back |
| STANDBY | 120, loop | mounted, looking about -- left, held, right, held, back; the head leads, the neck 2 f and the chest 4 f behind; the lance upright in his fist (owner: 骑在马上，不要下来，来回看) |

Gates: loops close exactly; jerk spike ratios ≤ 8.4 (MARCH ≤ 1.7). The idle loops' ratios read high only
because their motion is a few millimetres.

## Not done / known

* **Installed** (owner 2026-10-06: 接进游戏，替换掉原来的骑兵) by `install.py`: `cavalry_rigged.glb` ->
  `assets/3D/units/cavalry/cavalry.glb` -- clips `cavalry_X` -> `X`, `R_Head` -> `head` (the chip's bone),
  `Head` -> `head_h`, the rig turned half round to face glTF −Z like every piece, the maps re-encoded JPEG under
  their old names; then Godot's import (the scene and the `.import`'s loops carry over by name).
  `army_art.csv` cavalry `stride_m` 5.9 (the canter's 2.4 m × 2.47); `units3d.json`; the art kit's specs
  re-extracted (DEFEND optional). An independent critic passed the swap in the game window (2026-10-06); its
  nit on the canter's head carriage raised the nod to 9 / 6 / 7 deg. The spy courier borrows this scene: GALLOP / IDLE fall back to
  MARCH / GARRISON. DEFEND has no caller in the game yet.
* Where a plate lay on the saddle the old pipeline culled the faces it hid, so the rider never leaves the
  saddle in any clip (the first STANDBY dismounted and showed the gaps; the owner had him stay mounted).
  Plates are rigid, so a far-raised arm opens a gap at the pauldron (no clip raises it that far).
