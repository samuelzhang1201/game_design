# Settlement houses from Tripo 3D

Since 2026-09-30 every house type in `data/map3d_houses.csv` is a Tripo 3D generation
(owner: 重构房屋3d模型), and the church and palace keep every version the owner exported
as a variant (`church_b`, `palace_b`, `palace_c`). Generated on the owner's **paid** plan
only — paid-plan outputs are ours (Tripo terms §5.2.2), free-tier ones are Tripo's.

## Sources

| step | where |
| --- | --- |
| reference picture | `tools/map3d/gen_house_refs.py` (Z-Image and Qwen-Image-2512 side by side; the owner picked Qwen) → `assets/3D/buildings/<type>/model_wip/<type>_ref_<model>[_vN].png` |
| Tripo generation | the owner, in Tripo's web studio: single image, high-detail model, texture 2K, de-lighting ON, PBR, private |
| GLB | `assets/3D/buildings/<type>/model_wip/tripo/<type>_tripo[_vN].glb` (git-ignored, ~100k triangles) |

`JOBS` in `tripo_houses.py` names each game type's source, its yaw (the door to -Y), its
triangle budget, its atlas size and whether its roof takes the runtime's roof tints.

## Run (in the owner's open Blender, through the Blender MCP)

```python
T = {}; exec(open("/Users/samuelzhang/game_design/tools/map3d/tripo_houses/tripo_houses.py").read(), T)
T["load_all"]()      # every source into the scene Tripo_Houses, fitted to its footprint
T["build_all"]()     # reduce, split, uv, bake, footing, grime — about a minute for all 17
T["arrange"]()       # each source with its game model in front of it, for the look
T["export_all"]()    # assets/3D/buildings/<type>/<type>.glb, the CSV's sizes, houses.json
```

Then `Godot --headless --path . --import` (keep `project.godot` as it was: a headless
import drops its renderer lines) and `tools/map3d/build_pack.sh` (the house table is in
the world's `steps_hash`). A new type's `<type>.glb.import` must carry
`meshes/force_disable_compression=true` like the others (copy one).

## What it does, and the traps that shaped it

* **A voxel shell before the collapse.** Straight onto Tripo's tile-by-tile roofs a 1%
  collapse tore them into spikes; remeshed first (the footprint / 140, never over 0.2 m)
  the surfaces are clean and closed, so no hole survives.
* **Not for the palaces** (`SHEETS`): their walls are single open sheets and the base is
  one 94 m hole, so a remesh has no inside — palace v1 came back a bare courtyard at 0.49 m
  and a solid wedge at 0.2 m. They are welded FIRST (Tripo splits every vertex on a
  texture seam: 53,129 open edges raw, 1,183 welded — collapsed first, the seams drift
  apart for good), filled, collapsed, fanned, pinched and tidied until `census()` — the
  mesh test's own census, keyed by millimetre position — finds no hole a metre across and
  no flipped face. Degenerate slivers are dissolved before export: the glTF exporter drops
  them and reopens the hole.
* **One atlas, two surfaces.** Roof faces (normal rising past `ROOF_NZ`, above
  `ROOF_ABOVE` of the height) are slot 0, the wall slot 1: Godot's glTF import leaves vertex
  colour off on a mesh's first surface, and the wall carries the grime.
* **The atlas is pre-filled** with the source texture's mean colour and never cleared: on
  black, the gutters and missed texels bled black into every mip.
* **The footing** is traced from the walls' cross-section `SLICE_Z` above the floor, and
  takes its UVs from the wall's own foot only — the eaves' roof UVs painted it orange.
