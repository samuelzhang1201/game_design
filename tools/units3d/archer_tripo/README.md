# The longbowman, v2 (the archers' piece)

Owner 2026-10-08: 使用此文件的绑骨方式，参考走路方式，然后加上弓箭 — the same longbowman regenerated
by Tripo 3D (the owner's paid plan) in a T-pose, without his bow and quiver, and **auto-rigged by
Tripo** (a 61-bone UE-style skeleton with fingers and twist bones; it came with its own walk / run /
idle, which are not used: the owner kept the v1 run). The bow and the quiver are the **v1 model's**
(`tools/units3d/archer_rig/`, cut out of it), put in his left fist and on his back; the five clips
are v1's, **ported** onto this skeleton. Worked in a Blender of its own on port 9877; every call
execs the files it needs into one dict:

```python
G = {}
for f in ("common", "build", "actions", "validate", "export"):
    G["__file__"] = ".../tools/units3d/archer_tripo/%s.py" % f; exec(open(G["__file__"]).read(), G)
G["build_all"]()          # import -> props -> rest -> five clips baked
G["export"]()             # -> model_wip/tripo_v2/archer_rigged.glb
```

then `tools/units3d/archer_install/install.py` (→ `assets/3D/units/archers/archers.glb`, two
surfaces), Godot's import, `archer_install/make_scene.gd` (a material per surface; an `-s` run
drops the scene's `ext_resource` UIDs and the art table's — put them back from the `.import` files,
and `git checkout` the table if only its UIDs moved). The props' textures need the body's import
settings (Basis Universal; the normal map's `roughness/src_normal`).

## Sources (git-ignored, `assets/3D/units/archers/model_wip/tripo_v2/`)

| file | what it is |
| --- | --- |
| `archer_v2_rigged_tripo.glb` | the owner's Tripo export: 98.6k tris, skinned, three clips |
| `props_from_v1.glb`, `props_info.json` | the v1 bow and quiver cut out of `archer_rig_work.blend` (its `bow` / `quiver` labels, the v1 string and arrow left out), and the v1 rig's rest frames they were cut from |
| `archer_tripo_work.blend` | the working scene `Archer_Tripo` |
| `archer_rigged.glb` | `export.py`'s export |
| `shots/` | the phase checks |

## Phases

| phase | where | what |
| --- | --- | --- |
| A | `build.import_tripo` | one armature `archer_rig`, one mesh `archer`; crown at 1.85 m (×1.886); each limb bone's tail put on the next joint (the import guesses tails), the toe laid level; Tripo's clips and posed frame dropped; the body collapsed 98.6k → 17k tris (the weights interpolate, Tripo's normal map keeps the detail) |
| fingers | `build.pose_fingers` | each finger curls about its own axis (the T-pose's palms face down); `FIST` closes round the bow's grip, the thumb (`THUMB`, fitted) lies across the index's middle joint |
| B | `build.build_props` | the v1 bow into the fist — its grip in the fist's hole (`fist_centre`: the fingers' ring, centred within 2.5 mm), its chord along the knuckles (the upper tip on the thumb's side, as v1), the string toward the forearm; the quiver at v1's height on the chest, its inner face 6 mm off this back; the coat-green scraps cut out with them dropped by their texture colour; the grip, torn where v1's fist was welded to it, cut out (±13.5 cm) and bridged with a round leather-wrapped grip |
| C | `build.weight_and_join` | bones `Bow` (in `hand_l`), `BowLimb.U/.D`, `String`, `Arrow`, `Quiver` (in `spine_03`); the bow rigid on `Bow` over the grip and graded into the limbs, the quiver rigid; v1's drawable string and 76 cm arrow rebuilt on spots of the props' texture; all joined into `archer` (a `part` attribute: body / bow / string / arrow / quiver), the props keeping their own material — **two surfaces** (`archer_body`, `archer_props`); 21.3k tris in all |
| rest | `actions.rebind_rest` | the bind pose made a man at ease with **every joint untwisted** (the left upper arm hanging, the elbow square, the hand at its own angle — which holds the bow upright —, the right arm hanging): the game sizes and spaces a piece by its mesh's box (a T-pose and a level bow: 2.5 m wide; now 0.77 × 0.85 × 1.85 m), and a pose with a turned wrist bakes its twist into the skin. The limbs' hinges and the fingers' axes are kept on the bones first (custom properties: local axes go with the bone) |
| clips | `actions.py` | v1's solver, ported: v1 names through `common.BN`; a knee or an elbow solved about its own rest hinge (`HINGE_REST` → `set_hinged`, no roll assumed); a local Euler on a Tripo bone keeps v1's meaning (`v1_frame`); v1's one chest bone is `spine_02` + `spine_03`, half each; the run's right arm a chain from the shoulder; the toe flat on the ground while the heel rises; the fingers per clip (`rgrip`, `rhook`: a runner's fist, the hook on the string, the pinch of an arrow, the release) |
| 6 | `validate.py` | `clip_metrics`, `limb_twist`, `clearance` (the closest a prop comes to the body; the right hand's touch on the bow counts) |
| 7 | `export.py` | one NLA track a clip; the rig and mesh unhidden for the export |

## The clips (30 fps, all loops, in place)

As v1 (`tools/units3d/archer_rig/README.md`), ported: MARCH 24 f (the run after the owner's
8-phase sheet; the left arm a hanging chain with the bow tilted forward-down — on this hand the
fit is `L_PRON` 10°, `L_DEV` −14°, the wrist taking back `BOW_STEADY` half the forearm's swing: the
bow 20–42° below level, fore and aft; the right arm's elbow placed where its swing puts it, never
the mirror), GARRISON 150 (its anchor 4 cm further forward and 3 cm lower than v1's: the string
clear of this sallet's brim by 4.8 cm),
ATTACK 48, DEFEND 80 (the bow tilted ~20°, the flinch ~1.6× v1's), STANDBY 150.

Gates: every loop closes exactly; every IK target reached; no toe under the ground; the run's
planted toes slip ≤ 1.6 mm a frame; the bind pose's twist 0; the clips' forearm twist ≤ 23° (the
wrist ≤ 23°, DEFEND / STANDBY: the bow held crosswise / stood up); the fastest single-frame turn
is a finger's at ATTACK's release (the string let go).

## Known limitations

* The quiver and the bow keep v1's texture (a second material, `archers_props`, 1024 px).
* Close up, Tripo's coat is collapsed to 17k tris: its quilting is the normal map's.
* The right hand rests on, or hooks, the bow and string in GARRISON / ATTACK / DEFEND / STANDBY:
  `clearance` reports that touch as ~1–5 mm.
