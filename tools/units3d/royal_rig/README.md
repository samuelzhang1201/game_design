# The king on horseback (the royal regiment's piece)

Rigged and animated by the **blender-auto-rig** skill's phases (owner 2026-10-06: 用 blender-auto-rig
技能重新操作 — not the cavalry pipeline), in the owner's open Blender through the MCP. Every phase is a
function in this folder; MCP namespaces do not persist, so each call execs `common.py` and the
phase files it needs into one dict:

```python
G = {}
for f in ("common", "labels", "weights", "validate", "armature", "actions"):
    G["__file__"] = ".../tools/units3d/royal_rig/%s.py" % f; exec(open(G["__file__"]).read(), G)
```

## Sources (git-ignored, `assets/3D/units/royal/model_wip/tripo/`)

| file | what it is |
| --- | --- |
| `medieval+knight+on+horse+3d+model.glb` | the Tripo generation (owner's paid plan) from `REF_royal_qwenfast_s1.png`: one fused textured mesh — **the deliverable** |
| `medieval+knight+3d+model+parts.glb` | the same generation's 47 untextured parts — a **label source only** (Phase 1d) |
| `royal_rig_work.blend` | the working scene `Royal_Rig` (textures packed) |
| `royal_rigged.glb` | the Phase 6 export: mesh + 52-bone skin + the five clips |
| `shots/` | gate renders: `gate3_*.png`, `poses_*.png`, `royal_clips_overview.png` |

## Phases

| phase | where | what |
| --- | --- | --- |
| 1c | (inline, recorded in the report) | faced −Y, left +X: yaw 90° + 17.02° measured from the leg pairs, scaled so the horse is 2.45 m nose to tail, centred on the leg pairs, hooves on z = 0, doubles merged |
| 1d | `parts_sheet.py`, `parts.csv`, `labels.py` | parts ICP-aligned (0.49 % / 1.43 % of height), identified on contact sheets, role table (every part once); labels by nearest part + 3-pass majority; reins found by thickness (`straps`, never flooding into the rider or the sword) |
| budget | — | the fused mesh collapsed 95k → 19,000 tris before labelling (the game's 20k budget); the 4K Tripo maps ride its UVs |
| 2 | `common.grid_render`, `grid_overlay.py` | leg slices, gridded x-ray side / front renders, part junctions |
| 3C | `armature.py` | 52 bones: the skill's horse template, `Saddle` (non-deform) → the `R_` rider, `Sword` on the right hand, `Reins` (the rein hand's place, never its turn) |
| 4b–4d | `weights.py` | normalised distance competition for the mixed saddle-and-thigh part and contacts; heat solve per region (numpy PCG: Blender's Python has no scipy), rider sub-group masks and cut edges, the barrel kept off the leg bones; props rigid with a 4-ring blend; reins graded bit → `Reins`; seams split rider / mount / reins / rider's arms |
| 5 | `validate.py` | numeric gates (all 0), the stretch table, the weight map, test poses |
| clips | `actions.py` | `all_clips()`: MARCH (gallop, 24 f), GARRISON (sword pointed forward, 120 f), ATTACK (rear + cut, 90 f), DEFEND (rear + high parry, 80 f), STANDBY (dismounted, leading the horse, 120 f), 30 fps, keyed from 0 |

## Known limitations

* Where one body covered another at rest, the split shows a gap when they part: the saddle under the
  king's thighs when he dismounts (STANDBY), the surcoat behind his right forearm when the sword arm
  rises, a pale line on the neck where a rein lay.
* The stirrup irons were decimated into the boots, so they leave with his feet in STANDBY.
* The runtime blends clips: STANDBY ↔ any mounted clip slides the king through the horse for the
  blend's length.
* The piece faces −Y (the skill's frame); the cavalry / courier pieces face +Y.
