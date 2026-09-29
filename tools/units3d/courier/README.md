# The courier rider (sub-project D)

The mounted courier the 3D map draws for every `ordinary` and `secret` courier
(`data/courier_art.csv`): the owner's design C4 (`assets/flux/out/courier_designs/zimage_C4_s2.png`,
spec `docs/superpowers/specs/2026-09-28-courier-art-design.md` §2) — a herald on a white dapple horse, blue
tabard with a gold cross, grey hat and feather, dispatch case, and a pennon on a staff.

## Rebuild: one command

```
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
    --python tools/units3d/courier_build.py -- courier
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

The Qwen tiles (`qwenfast_*`) were looked at and not used: several are objects (horse photos, a
saddle, framed plates, a stitched panel), the rest knit, burlap or moss rather than the cloth wanted.

## The scripts

| file | what it does |
| --- | --- |
| `../courier_build.py` | the one command: rebuild → rig → actions → export |
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

45 bones. The horse's are `cavalry_scan.rig_spec`'s on the same scan (its leg tops scaled from the
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
that stance takes — the model metres one GALLOP loop covers (3.282).
