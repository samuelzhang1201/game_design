# The king on horseback (the royal regiment's piece)

`assets/3D/units/royal/royal.glb` since 2026-10-06 (owner: 替换掉原本的文件，应用到游戏中去). The owner
rigged and animated the Tripo generation (paid plan, from `REF_royal_qwenfast_s1.png`) in Blender and
delivered the export; this folder only INSTALLS it:

```bash
Blender -b <tripo>/knight_rig_anim.blend --python tools/units3d/royal_install/decimate.py   # -> knight_rigged_20k.glb
python3 tools/units3d/royal_install/install.py        # knight_rigged_20k.glb -> royal.glb
Godot --headless --path . --import                       # extracts royal_royal_atlas{,_n,_mr}.jpg
Godot --path . -s res://tools/units3d/royal_install/make_scene.gd   # first time only
```

`make_scene.gd` writes `scenes/models/units/royal.tscn` (inherits the `.glb`, its own material on the
extracted maps) and points `army_models.tres`'s `royal` at it. An `-s` run drops the `ext_resource`
UIDs: put them back (or re-save from the editor). A re-delivery is `decimate.py`, `install.py` and the import alone:
the scene, its material and the `.import` (MARCH / GARRISON / STANDBY loop; ATTACK and DEFEND one
shot; `force_disable_compression`, as the cavalry's) all carry over.

## Sources (`assets/3D/units/royal/model_wip/tripo/`, git-ignored)

| file | what it is |
| --- | --- |
| `knight_rigged.glb` | **the delivery**: one 90k-tri mesh, 59 bones, ATTACK / DEFEND / GARRISON / MARCH / STANDBY at 30 fps, 4K maps |
| `knight_rig_anim.blend` | the owner's rig and animation scene it was exported from (never saved over) |
| `knight_rig_anim_20k.blend`, `knight_rigged_20k.glb` | `decimate.py`'s output: the same scene collapsed to 20k tris (owner 2026-10-06: 减面到2万左右), and its export — **what the game installs** |
| `knight_preview/` | the owner's GIFs of each clip and the gallop's footfall chart |

## What `install.py` changes, and why

* **Turned half round** (root rotation 180° about up): the delivery faces Blender −Y (glTF +Z);
  every piece faces Blender +Y (glTF −Z), which `Map3DUnits.yaw_for` assumes.
* **Two bones renamed**: `R_Head` → `head` (the headcount chip hangs over the bone named `head`,
  `Map3DUnitRig.head_m`), the horse's `Head` → `head_h`, as on the cavalry.
* **Maps** 4096 → 2048 JPEG, named `royal_atlas` / `_n` / `_mr` (one 2048 atlas per unit, like the
  cavalry and the infantry).
* Nothing else: the mesh (as `decimate.py` left it), the skin and the clips are the delivery's.

`decimate.py` applies a Collapse Decimate UNDER the Armature modifier (90,506 → 19,998 tris, 11.7k
verts): Collapse interpolates the vertex groups, so every vertex stays skinned and the clips carry
over; side by side in Blender the reins, sword and saddle cloth hold, only the pauldrons shade a
little harder.

## Open

* `size` 0.72 keeps the horse at the cavalry's scale (the knight has no lance to stand tall by). `stride_m` (`data/screens/map3d/army_art.csv`) is the measured gallop stride times the factor the cavalry and the
  infantry were tuned by — judge it on a march.
* No `royal_parts.glb`: the folio's Take apart stays hidden for the king. The art kit's
  `specs.json` (`tools/art_kit/extract_specs.py` `UNITS`) does not list the royal model yet.
* The 20k collapse stair-steps the saddle cloth's gold trim at its rear edge, visible only close
  up in Blender (independent critic 2026-10-06; in game the two are indistinguishable). Pin that
  border in a vertex group (`Decimate.vertex_group`) if the WAR ROOM's close look ever shows it.
