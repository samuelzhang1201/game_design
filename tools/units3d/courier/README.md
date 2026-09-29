# The courier rider (sub-project D)

The mounted courier the 3D map draws for every `ordinary` and `secret` courier
(`data/courier_art.csv`): the owner's design C4 (`assets/flux/out/courier_designs/zimage_C4_s2.png`,
spec `docs/superpowers/specs/2026-09-28-courier-art-design.md` §2) — a herald on a white dapple horse, blue
tabard with a gold cross, grey hat and feather, dispatch case, and a pennon on a staff.

**Two sources, one pipeline.** The shipped courier is the owner's **Tripo 3D** model (the default
`--source tripo`, `tripo.py`, below); the earlier from-scratch build, **v3** (the CC0 scan horse and
the base-mesh rider), stays buildable as `--source v3`.

## The Tripo source (the default)

The owner generated the piece in Tripo 3D from our pick and supplied two models of the same rider
(git-ignored, `assets/units3d/ai_src/courier/tripo/courier/`): `textured.glb` (one fused mesh, 93k
tris, colour + normal + metal-roughness at 4096 px) and `parts.glb` (the same shape as 43 untextured
parts). The PARTS ship; `tripo.py`:

1. fits the parts onto the textured mesh (ICP: a similarity transform, residual ~2.5 mm at native
   size), turns the piece to face +Y, scales the horse to 2.45 m nose to tail, stands the planted
   hooves on z = 0, and drops the parts' faces the fused mesh does not have (a far leg's stub inside
   the rump: hidden at rest, a flap in motion);
2. reduces each part to its budget in `tripo_parts.csv` (scaled to <= 19,400 tris together);
3. unwraps every part into one 2048 atlas and bakes the textured mesh onto them: colour in two
   passes (a far pass with a long cage for faces inside other parts, then the near pass over it),
   metal-roughness, and the tangent normal (the face keeps a flat normal: its bake washed it out);
4. lays the skeleton — the cavalry's horse bone NAMES found on this horse part by part (it walks:
   one foreleg raised, one hind hoof lifted, so `cavalry_scan.rig_spec`'s hoof probe cannot be used
   as is) and make_units' mounted rider names on the rider's own parts — and weights it:
   `tripo_parts.csv`'s `weights` column (bone heat on each horse part; the rider's parts from bone
   heat solved on a welded copy of the fused mesh; rigid; the reins graded head -> near fist; the
   pennon graded along its fly);
5. the raised foreleg stays raised in the rest pose and is straightened in every key
   (`rig.NEUTRAL`); the staff rides the off hand, the reins the near fist.

`tripo_parts.csv` names all 43 parts (`part`, `role`, `group`, `weights`, `tris`, `texel`).

## Rebuild: one command

```
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    --python tools/units3d/courier_build.py -- courier [--source tripo|v3]
```

~90 s headless (Metal GPU for the bakes). It rebuilds the static model, rigs it, authors the
actions, measures the stride, and writes `assets/units3d/courier.glb` and the `courier` entry of
`assets/units3d/units3d.json`. Then:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
```

`assets/units3d/courier.glb.import` is committed with `meshes/force_disable_compression=true`,
`animation/fps=24` and both clips set to loop (`_subresources`); Godot extracts the embedded atlas
as `assets/units3d/courier_courier_atlas*.jpg`, which are git-ignored like every unit's.
`data/courier_art.csv`'s `stride_m` is the `STRIDE_M` the build prints.

The static model alone (no rig, for look work) is
`Blender -b --factory-startup --python tools/units3d/courier/rebuild_v3.py`, which saves
`assets/units3d/ai_src/courier/courier_v3.blend` and `audit_v3.json`.

## Sources and licences

All git-ignored and read where they are; nothing here is committed but the scripts.

| source | where | licence |
| --- | --- | --- |
| The Hunt Museum "Horse Outside" scan (the horse's shape) | `cavalry_scan.SRC` + `hunt_horse/`, through `cavalry_scan.horse_source()` | CC0-1.0 |
| Blender Human Base Meshes bundle v1.4.1, `GEO-body_male_realistic` and its Multires sculpt (the rider) | `assets/units3d/ai_src/courier/human_base_meshes/` (see its `SOURCE.txt`) | CC0 |
| Z-Image material tiles T1–T7 (coat, wool, leather, gold, brass, felt, canvas) | `assets/flux/out/courier_tiles/zimage_T*_s*.png` (`tools/units3d/gen_courier_tiles.py`) | our own renders (Z-Image Turbo; see `assets/flux/README.md`) |
| The design pick | `assets/flux/out/courier_designs/zimage_C4_s2.png` | our own render |
| **The Tripo 3D courier** (`textured.glb`, `parts.glb`; the default source) | `assets/units3d/ai_src/courier/tripo/courier/` | the owner's own generation in Tripo 3D from our pick; commercial rights per the owner's Tripo plan. The raw Tripo files stay git-ignored. |

The Qwen tiles (`qwenfast_*`) were looked at and not used: several are objects (horse photos, a
saddle, framed plates, a stitched panel), the rest knit, burlap or moss rather than the cloth wanted.

## The scripts

| file | what it does |
| --- | --- |
| `../courier_build.py` | the one command: build (`--source tripo` or `v3`) → rig → actions → export |
| `tripo.py`, `tripo_parts.csv` | the Tripo source: align, cull, reduce, bake, skeleton, weights |
| `rebuild_v3.py` | the static model: build, texture, clean, audit (the `3d-model-build-up` skill's `audit_game`, ≤ 20,000 tris, one material) |
| `build_v3.py` | the horse, the seated rider in costume, tack, clothes, props, mane and tail, eyes, boot bands |
| `scan_horse.py` | the cavalry's Hunt scan at 2.45 m, re-centred on its barrel |
| `human.py`, `rider_pose.py`, `costume.py` | the base-mesh rider: load (Multires level 2), a temporary 17-bone seat pose, costume regions, painted face, sculpted fists, boot feet |
| `tack_v3.py`, `clothes_v3.py`, `props_v3.py`, `hair_v3.py` | the pieces laid on the scan and the posed body by ray casts against their mesh fields |
| `meshfield.py` | a BVH mesh as a signed-distance field with exact rays |
| `texture_v3.py` | reduce to the budget, unwrap, paint (box-projected tiles, a procedural dapple), bake the 2048 atlas (colour + light AO, normal, metal-roughness), join; each vertex keeps a `part_id` for the rig |
| `rig.py` | the skeleton, the weights part by part, GALLOP and IDLE, the stride |
| `sdfkit.py`, `cage.py`, `hair.py`, `horse_sdf.py` | v1's SDF, cage and lock helpers the pieces are built with |

## The rig

45 bones in both sources (v3 described here; tripo above: the same names, the staff on the
off hand). The horse's are `cavalry_scan.rig_spec`'s on the same scan (its leg tops scaled from the
cavalry's 2.60 m horse to 2.45 m); the rider's carry make_units' mounted names on the joints the
build posed him on; `pole` (+ `pennon_1`, `pennon_2`) and `case` hang on the saddle. Weights: bone
heat for the horse and the rider's body (each over its own bones, by-distance fallback), the rest
by distance or rigid per part; the build refuses to export if 1% or more is unweighted.

## The actions

Both keyed as poses, then baked through IK (both feet to the stirrups, the left fist to the
staff) so the rider can rise and pitch without leaving the irons or the pole; the IK helpers are
dropped after the bake. Keyed from frame 0 so the glTF clip runs exactly 0..N/24 s.

* **GALLOP**, 24 frames at 24 fps, a loop: a four-beat transverse gallop — near hind, far hind,
  near fore, far fore (`rig.FOOTFALL`), then the suspension; the rear carried at the height of the
  lowest hind hoof down and the front pitched to the lowest fore hoof down, a leap in the
  suspension; neck and head swinging, the tail streaming, the rider up in the irons ~15° forward
  and rocking against the horse, the pennon streaming, the case bouncing a frame behind.
* **IDLE**, 72 frames, a loop: weight shifting between the hind legs, one tail swish, one head
  nod; the rider looks left and back.

`stride_m` is how far the near hind hoof moves back through its stance over the share of the loop
that stance takes — the model metres one GALLOP loop covers (tripo 2.479; v3 3.282).

Per source (`courier_build.build_tripo`): the reins side (`rig.REINS`), the IK arm (`rig.IK_ARM`;
none for tripo, whose staff rides the hand), the hind swing (`rig.HIND_SWING`, 22° for tripo) and
how far the tail streams (`rig.TAIL_STREAM`, 0.4 for tripo: the tail covers a notch in the rump the
model never textured).
