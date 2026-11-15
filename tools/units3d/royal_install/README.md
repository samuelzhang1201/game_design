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

* `size` 0.72 keeps the horse at the cavalry's scale (the knight has no lance to stand tall by).
* No `royal_parts.glb`: the folio's Take apart stays hidden for the king. The art kit's
  `specs.json` (`tools/art_kit/extract_specs.py` `UNITS`) does not list the royal model yet.
* The 20k collapse stair-steps the saddle cloth's gold trim at its rear edge, visible only close
  up in Blender (independent critic 2026-10-06; in game the two are indistinguishable). Pin that
  border in a vertex group (`Decimate.vertex_group`) if the WAR ROOM's close look ever shows it.

## The pivot for any turn

`scripts/map3d/map3d_royal_pivot.gd` (`Map3DRoyalPivot`) poses a royal pivot of any turn that leaves and
rejoins MARCH at the plan's phase (`assets/3D/units/royal/royal_pivot_plan.json`); `pivot.py`'s baked
clips stay installed but no provider plays them. To look at it in a real window (never `--headless`):

```bash
Godot --path . -s res://tools/units3d/royal_install/pivot_frames.gd -- --out DIR --turn 90000000 [--mode native] [--plan lift_m=0.04]
```

## The re-keyed MARCH (LOCO-ROY-MARCH, owner ruling R-J 2026-11-13)

The delivered gallop's planted hooves slid and its toes broke over into the ground (certifier:
slide 339,795 µm, penetration 36,419 µm, against contact 29,338 µm). Its hoof chains, and nothing
else, are re-keyed:

```bash
git checkout assets/3D/units/royal/royal.glb && Godot --headless --path . --import   # the delivered clip
Godot --headless --path . -s res://tools/units3d/royal_install/march_reauthor.gd -- --out KEYS.json
python3 tools/units3d/royal_install/march_transplant.py assets/3D/units/royal/royal.glb KEYS.json
Godot --headless --path . --import
```

(numeric only, so `--headless` is safe; the frames below are not). `march_reauthor.gd` samples the
delivered MARCH at 64 intervals:

* **Stances**: a hoof stands where its sole patch is within 6 mm of the seated plane, until its toe
  is deepest in the break-over (past it the native toe rises).
* **Stride**: S is the least-squares ground speed of the planted soles. It is `army_art.csv`
  `stride_m`, measured off the clip, never tuned.
* **Planted hoof**: one frame, the native rotation where the patch is flattest, carried back at
  exactly S. It rolls as the native hoof rolls, about the hull vertex that roll brings lowest (the heel
  landing, the toe breaking over), which stays put. Its hull (every vertex mostly on the hoof bone)
  is settled on the plane.
* **Swing**: the native path, shifted by a correction that eases from lift-off's error to
  touchdown's. Its first and last three keys blend from the planted motion carried on, so a hoof
  leaves and meets the ground at zero ground speed. A leg already at full reach takes a scaled
  correction.
* **The pivots' admitted phase** (`royal_pivot_plan.json` `march_phase`, the pivots' entry, exit and
  hold) is the delivered pose exactly. A hoof planted across it passes through its native frame
  there, seated at that sole's height; one landing on it stands from the next key; one in the air
  takes no correction there. The R-B skin rule measures every pivot against that pose.
* Only the 18 hoof-chain rotations change (`Map3DCavalryPivot`'s chain IK). In the GLB, the other
  bones, every origin and scale, and the other clips are the delivery's, byte for byte. The 120 fps import
  re-samples every clip's playback, and the certifier's pivots, hold and skin checks read that
  playback. Key 64 is key 0, which closes the hoof
  chains' 2.3 mm loop seam.

`march_transplant.py` (test: `test_march_transplant.py`) first checks that Godot's bone locals are the
GLB's own keys. It then appends the 18 channels and repoints their samplers; every original byte is
kept. `royal.glb.import` imports at `animation/fps` 120: at 30 Godot re-bakes MARCH to the delivered
17 keys, and at 240 the native-jets proof (`Map3DRoyalNativeJets`) cannot cover the 1e-5 s cut
before each key (it needs keys at least 5.12 ms apart). `royal_locomotion_source.tres` pins the new
digests; its observations stay those of the delivered clip. Evidence:
`docs/reviews/cluster-formations/evidence/locomotion/royal/march-reauthor/`.
