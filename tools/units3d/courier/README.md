# The courier rider (sub-project D)

The mounted courier the 3D map draws for every `ordinary` and `secret` courier
(`data/courier_art.csv`): the owner's design C4 (`assets/flux/out/courier_designs/zimage_C4_s2.png`,
spec `docs/superpowers/specs/2026-09-28-courier-art-design.md` §2) — a herald on a white dapple
horse, blue tabard with gold shoulder pieces, grey hat and feather, dispatch case, and a pennon on a
staff — as the owner modelled it in **Tripo 3D** from that pick.

## Rebuild: one command

```
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    --python tools/units3d/courier_build.py -- courier
```

~90 s headless (Metal GPU for the bakes). It builds the model, rigs it, authors the actions,
measures the stride, and writes `assets/units3d/courier.glb` and the `courier` entry of
`assets/units3d/units3d.json`; the rigged file is saved to
`assets/units3d/ai_src/courier/courier_rigged_tripo.blend` for shots. Then:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
```

`assets/units3d/courier.glb.import` is committed with `meshes/force_disable_compression=true`,
`animation/fps=24` and both clips set to loop (`_subresources`); Godot extracts the embedded atlas
as `assets/units3d/courier_courier_atlas*.jpg`, which are git-ignored like every unit's.
`data/courier_art.csv`'s `stride_m` is the `STRIDE_M` the build prints (2.338).

## Sources and licences

| source | where | licence |
| --- | --- | --- |
| **The Tripo 3D courier**: `textured.glb` (one fused mesh, 93k tris, colour + normal + metal-roughness at 4096 px) and `parts.glb` (the same shape as 43 untextured parts) | `assets/units3d/ai_src/courier/tripo/courier/` (git-ignored) | the owner's own generation in Tripo 3D from our pick; commercial rights per the owner's Tripo plan. The raw Tripo files stay git-ignored. |
| The design pick | `assets/flux/out/courier_designs/zimage_C4_s2.png` | our own render |
| The horse bone names and the rig / weight helpers | `tools/units3d/cavalry_scan.py` (`rig_spec`'s names), `model_cavalry.py`, `make_units.py` | this repository |

## The scripts

| file | what it does |
| --- | --- |
| `../courier_build.py` | the one command: build → rig → actions → export |
| `tripo.py` | the model: align, cull, reduce, unwrap, bake, the skeleton, the weights |
| `tripo_parts.csv` | all 43 parts: `part`, `role`, `group`, `weights`, `tris`, `texel` |
| `rig.py` | the bone sets, GALLOP and IDLE, the IK bake, the stride |
| `texture.py` | the atlas images, the selected-to-active bake, the one atlas material |

## The model (`tripo.py`)

1. Fits the parts onto the textured mesh (ICP: a similarity transform, residual ~2.5 mm at native
   size — the two files are two generations of one shape), turns the piece to face +Y, scales the
   horse to 2.45 m nose to tail, stands the planted hooves on z = 0, and drops the parts' faces the
   fused mesh does not have (a far leg's stub inside the rump: hidden at rest, a flap in motion).
2. Reduces each part to its budget in `tripo_parts.csv` (scaled to <= 19,400 tris together; the
   build refuses over 20,000).
3. Unwraps every part into one 2048 atlas (smart project at 80°) and bakes the textured mesh onto
   them: colour in two passes (a far pass with a long cage for faces inside other parts, then the
   near pass over it), metal-roughness, and the tangent normal (the face keeps a flat normal: its
   bake washed it out under the hat's brim).
4. Lays the skeleton — the cavalry's horse bone NAMES found on this horse part by part (it walks:
   one foreleg raised, one hind hoof lifted, so `cavalry_scan.rig_spec`'s own hoof probe cannot be
   used) and make_units' mounted rider names on the rider's own parts — and weights it by
   `tripo_parts.csv`'s `weights` column: the horse from bone heat on a welded copy of the fused mesh
   (one surface across the parts' joins), the rump-and-trailing-leg shell by heat on itself, tail
   bones kept off every part but the tail; the rider's parts from rider-bone heat on the same copy;
   hat, hands, case, staff and tack rigid; the reins graded head → near fist; the pennon graded
   along its fly.

45 bones: the cavalry's horse names, make_units' rider names, `pole` (+ `pennon_1`, `pennon_2`) on
the off hand, `case` on the saddle. The build refuses to export if 1% or more is unweighted.

## The actions (`rig.py`)

Keyed as poses from `NEUTRAL` (the raised near foreleg straightened), then baked through IK (both
feet to the stirrups) so the rider can rise and pitch without leaving the irons; the IK helpers are
dropped after the bake. Keyed from frame 0 so the glTF clip runs exactly 0..N/24 s.

* **GALLOP**, 24 frames at 24 fps, a loop: a four-beat transverse gallop — near hind, far hind,
  near fore, far fore (`rig.FOOTFALL`), then the suspension; the rear carried at the height of the
  lowest hind hoof down and the front pitched to the lowest fore hoof down, a leap in the
  suspension; neck and head swinging, the tail streaming (`TAIL_STREAM` 0.4: it keeps covering a
  notch in the rump the model never textured), the hind legs swinging 22° (`HIND_SWING`: the rump
  and the trailing leg are one shell), the rider up in the irons ~17° forward and rocking against
  the horse, the pennon streaming, the case bouncing a frame behind.
* **IDLE**, 72 frames, a loop: weight shifting between the hind legs, one tail swish, one head
  nod; the rider looks left and back.

`stride_m` is how far the near hind hoof moves back through its stance over the share of the loop
that stance takes — the model metres one GALLOP loop covers (2.338).
