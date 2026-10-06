# The king on horseback (the royal regiment's piece)

`assets/3D/units/royal/royal.glb` since 2026-10-06 (owner: 替换掉原本的文件，应用到游戏中去). The owner
rigged and animated the Tripo generation (paid plan, from `REF_royal_qwenfast_s1.png`) in Blender and
delivered the export; this folder only INSTALLS it:

```bash
python3 tools/units3d/royal_install/install.py        # knight_rigged.glb -> royal.glb
Godot --headless --path . --import                       # extracts royal_royal_atlas{,_n,_mr}.jpg
Godot --path . -s res://tools/units3d/royal_install/make_scene.gd   # first time only
```

`make_scene.gd` writes `scenes/models/units/royal.tscn` (inherits the `.glb`, its own material on the
extracted maps) and points `army_models.tres`'s `royal` at it. An `-s` run drops the `ext_resource`
UIDs: put them back (or re-save from the editor). A re-delivery is `install.py` and the import alone:
the scene, its material and the `.import` (MARCH / GARRISON / STANDBY loop; ATTACK and DEFEND one
shot; `force_disable_compression`, as the cavalry's) all carry over.

## Sources (`assets/3D/units/royal/model_wip/tripo/`, git-ignored)

| file | what it is |
| --- | --- |
| `knight_rigged.glb` | **the delivery**: one 90k-tri mesh, 59 bones, ATTACK / DEFEND / GARRISON / MARCH / STANDBY at 30 fps, 4K maps |
| `knight_rig_anim.blend` | the owner's rig and animation scene it was exported from |
| `knight_preview/` | the owner's GIFs of each clip and the gallop's footfall chart |

## What `install.py` changes, and why

* **Turned half round** (root rotation 180° about up): the delivery faces Blender −Y (glTF +Z);
  every piece faces Blender +Y (glTF −Z), which `Map3DUnits.yaw_for` assumes.
* **Two bones renamed**: `R_Head` → `head` (the headcount chip hangs over the bone named `head`,
  `Map3DUnitRig.head_m`), the horse's `Head` → `head_h`, as on the cavalry.
* **Maps** 4096 → 2048 JPEG, named `royal_atlas` / `_n` / `_mr` (one 2048 atlas per unit, like the
  cavalry and the infantry).
* Nothing else: the mesh, the skin and the clips are the delivery's.

## Open

* **90,506 triangles**, four to five times the units' ~20k budget (the cavalry 19k): a full-strength
  royal regiment stands nine of them. Decimate in `knight_rig_anim.blend` (the weights survive a
  Decimate modifier) if the bench says so.
* `size` 0.72 keeps the horse at the cavalry's scale (the knight has no lance to stand tall by). `stride_m` (`data/army_art.csv`) is the measured gallop stride times the factor the cavalry and the
  infantry were tuned by — judge it on a march.
* No `royal_parts.glb`: the folio's Take apart stays hidden for the king. The art kit's
  `specs.json` (`tools/art_kit/extract_specs.py` `UNITS`) does not list the royal model yet.
