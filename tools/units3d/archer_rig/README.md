# The longbowman (the archers' piece)

Rigged and animated by the **blender-auto-rig** and **blender-natural-animation** skills' phases
(owner 2026-10-06: 请设计弓箭手的动作 — 行进奔跑 / 驻防拉弓搭箭 / 攻击不断射箭 / 防御弓横举在前 /
待命弓竖在地面手架在弓上), in a second Blender the owner opened for it (the first carried another
session's cavalry rig), its MCP server on port 9877. Every phase is a function in this folder;
MCP namespaces do not persist, so each call execs the files it needs into one dict:

```python
G = {}
for f in ("common", "labels", "armature", "weights", "validate", "props", "actions", "export"):
    G["__file__"] = ".../tools/units3d/archer_rig/%s.py" % f; exec(open(G["__file__"]).read(), G)
```

then `tools/units3d/archer_install/install.py` (→ `assets/3D/units/archers/archers.glb` and its
`units3d.json` entry), Godot's import, and the first time `archer_install/make_scene.gd`
(`scenes/models/units/archers.tscn`, `army_models.tres`'s `archers`; an `-s` run drops the
`ext_resource` UIDs — put them back from the `.import` files). The `.glb.import` loops all five clips.

## Sources (git-ignored, `assets/3D/units/archers/model_wip/tripo/`)

| file | what it is |
| --- | --- |
| `medieval+archer+3d+model.glb` | the Tripo generation (owner's paid plan) from `REF_archers_qwenfast_s2.png`: one fused textured mesh, 100k tris — **the deliverable** |
| `medieval+archer+3d+model+parts.glb` | the same generation's 41 untextured parts — a **label source only** (Phase 1d) |
| `string_fit.txt` | the line of Tripo's bowstring, fitted before it was cut out (Phase 1c) |
| `archer_rig_work.blend` | the working scene `Archer_Rig` |
| `archer_rigged.glb` | `export.py`'s export: mesh + 27-bone skin + the five clips |
| `shots/` | gate renders (`gate3_*`, `labels_*`, `wmap_*`, `poses_*`, `close_*`), clip sheets, `archer_*.gif` |

## Phases

| phase | where | what |
| --- | --- | --- |
| 1c | (inline) | already faced −Y, left +X; scaled ×1.889 so the helmet's crown is at 1.85 m (the infantry's), centred on the feet, doubles merged; Tripo's bowstring (welded to the bow, it could not be drawn) fitted as a line and deleted; collapsed 98k → 18.5k tris (the 4K maps carry the detail) |
| 1d | `labels.py` | parts ICP-aligned (median 0.79 cm), identified on `shots/parts_sheet.png`, a role per part; nearest-part labels, 3-pass majority; the bow told from the fist and the boot by its own centreline (the parts' bow is a separate generation 10 cm off), the bottom tip by walking the mesh |
| 3C | `armature.py` | 27 bones: a standing humanoid (`head` the chip's bone), `Quiver`, `Scabbard`, `Bow` in the left fist with `BowLimb.U` / `.D`, `String` (the nock point), `Arrow` |
| 4 | `weights.py` | heat solve per body sub-group with its own bones (the torso never follows an upper arm: a raised arm tore the chest), the arms' seams cut; the coat's skirt keeps 60 % on Hips and is smoothed; quiver, scabbard, buckler rigid with a 4-ring blend; the bow graded grip → tips; seams split, duplicates' roles fixed |
| props | `props.py` | the string (two strands graded tip → nock) and the 76 cm arrow (shaft, vanes, bodkin), textured from spots of the atlas, joined in; `cut_cuff_scraps()` deletes the leather flap Tripo welded under the right wrist and the skin shards it left on the coat |
| 5 | `validate.py` | numeric gates (all 0), stretch per test pose (raised arm 0, knee lift 34, twist 20 edges), weight map, test poses; `clip_metrics` per clip |
| clips | `actions.py` | every frame SOLVED from smooth channels (body-frame targets, lags down the chains): analytic two-bone IK with the hinge set explicitly (no flips), the left arm solved to hold the bow where the clip puts it, the string following the hooked hand, the arrow on the string / in the hand / hidden |
| 6/7 | `export.py` | one NLA track a clip, the debug colour layers dropped |

## The clips (30 fps, all loops, in place)

| clip | frames | what |
| --- | --- | --- |
| MARCH 行进 | 24 | a run after the owner's 8-phase sheet (2026-10-07: contact → down → passing → up/flight per step), duty 0.36, 2 m a loop (`stride_m` 4.9 = × the pieces' 2.47); the stance foot rolls heel → flat → toe on the belt, the swing a Hermite through the sheet's poses joined to the stance with no velocity step; the hips sink ~4 cm after the strike, rise in the push-off and are ballistic in the flight; the knees lifted low (owner: 抬腿稍低); the left arm LEADS and hangs in a J (`l_wrist`: the upper arm a little behind and out, the elbow bent `ELBOW_RUN` forward in the fore-and-aft plane only (`l_pole` straight back: a pole off it bulges the elbow out, a C from the front), the forearm angled a little further out than the upper arm (`ARM_OUT`, a man's carrying angle: never in, which reads as a C); the forearm pronated `L_PRON` 36°, half at each end (measured 18° at the elbow, 8° at the wrist), which turns the bow fore and aft beside him; the hand at its rest angle to the forearm but for an ulnar bend `l_dev` ≈ 38°): it swings against the left leg and the bow rides in the fist 16–42° below level, upper tip forward and down, rocking with the arm; the wood clears the body by 8.5 cm, the string the quiver by 2 mm. Owner 2026-10-07, in turn: 左手自然下垂并摆动，弓倾斜45度角向前下方; then 左手手腕和小臂扭曲严重 (a bow forced to 45° had twisted the forearm); then 呈一个C字形…应该是一个类J字形 (a straight arm with the wrist bent hard read as a C; then an elbow pushed out by a shoulder turn read as a C from the front). The fist holds the bow square to the forearm and is welded to it (turning the bow in the fist tears the grip), so with a J arm the tilt is what the arm and a natural wrist give |
| GARRISON 驻防 | 150 | side-on (the figure turned −90°, the shot along its march direction), an arrow nocked: half draw → full draw to the jaw → a held aim with a tremble → let down |
| ATTACK 攻击 | 48 | an arrow every 1.6 s: into the quiver, drawn up and over, nocked, raised to 14°, drawn, loosed (the arrow gone, the string straight, the hand past the ear), follow-through |
| DEFEND 防御 | 80 | crouched behind the bow held crosswise before the face; a blow at f 38, he gives and recovers |
| STANDBY 待命 | 150 | the bow stood on its bottom tip before his left foot, the left hand on the grip, the right resting on the upper limb; breathing, a weight shift, a look about |

Gates (`validate.clip_metrics`): every loop closes exactly; no toe under the ground; the run's
planted toes slip ≤ 4.8 mm a frame; the fastest bone turn is 38° a frame in ATTACK's arrow pull
(a real, continuous motion) and 25° a frame in MARCH's swinging foot (continuous), ≤ 15° elsewhere; every IK
target reached within 1 cm; MARCH's bow ≥ 2 cm off the body; `validate.limb_twist(clip)` reports each forearm's twist against its upper arm and each hand's
against its forearm (MARCH: the left forearm's pronation 18° at the elbow, 8° at the wrist; the right 0°).

## Known limitations

* The left fist is welded to the grip, so the bow never leaves the left hand: DEFEND turns the bow
  crosswise in it, STANDBY keeps it on the grip (the right hand rests on the limb).
* Where the seam split parted the arms from the coat, a raised arm shows a ragged edge at the
  shoulder (worst at the full draw, close up); at map scale it does not read.
* No arrow flies: the loosed arrow vanishes on the release frame (a projectile would be the map's).
* Nothing on the map plays ATTACK or DEFEND yet (no battle); the WAR ROOM's drill tabs do.
