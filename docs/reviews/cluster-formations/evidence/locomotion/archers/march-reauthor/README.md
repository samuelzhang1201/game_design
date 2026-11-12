# Archer MARCH re-author (2026-11-12)

Owner ruling (via the coordinating session, 2026-11-11): re-author the archer MARCH so the right toe
clears the ground in swing and the planted feet hold the ground. This is an explicit exception to the
protected-source-clip rule, for archer MARCH only. Every other clip, the mesh, skin, binds, gear, scale
and the stride (`army_art.csv` 1.5283) are unchanged.

## What was wrong

The exporter (`tools/units3d/archer_arp/export.py`) lifts each frame until its lowest body vertex
touches z = 0. In frames 12–17 (phase 0.31–0.46) the swinging right toe was that lowest vertex:
- it dragged along the floor for about 450 mm (model);
- the rest of the body floated up to 18.8 mm.

The planted feet also crept, from 25 to 69 mm, during stance and toe-off. Under the per-vertex slide rule
(#291), the shipped MARCH measures **512,453 µm** (per-foot band) against the archer bound of 28,474 µm (0.60 world m).

## What changed

All edits were made in the owner's Blender, on a copy of the export blend
(`assets/3D/units/soldier/model_wip/arp_archer_toeclear_20261111/archer_game_export.blend`, git-ignored).
Only the baked `game_MARCH` action was changed:

1. **Toe lift.** `toes_01.r` turns about its local −X over frames 12–19, eased in and out, at most
   0.6 rad. In the frames where the toe had set the floor lift, the body is lowered again, but never by
   more than leaves the toe 3 mm clear.
2. **Foot locks.** Each stance is held where it touched down:
   - left stance, frames 13–30;
   - right stance, frames 31–1 (anchored at frame 1, so the loop and the pivot entry are untouched);
   - right stance, frames 7–11.

   Each correction cancels the drift of the planted vertices, measured on 14 sub-frames per frame with
   linear interpolation (as Godot plays glTF). A two-bone IK in the leg's own plane carries the
   correction: thigh and shin rotate, foot and toe translate, every bone length is kept. The correction
   eases out over four swing frames.
3. **Frames 1 and 36 are byte-identical to the shipped clip.** MARCH phase 0, the loop seam and the
   pivots' MARCH ↔ PIVOT seams (842 µm) do not move.

`tools/units3d/archer_arp/march_transplant.py` then copied ONLY the edited MARCH channels from that
export into `assets/3D/units/archers/archers.glb`:
- it appends 21 new accessors (listed in `transplanted-channels.json`) and repoints their samplers;
- every original JSON table and BIN byte is preserved, as are the 198 unchanged MARCH channels, the
  other five clips and the appended pivots;
- the key times are unchanged.

GLB sha256: `02356e6f…` before, `f7112ff7…` after.

## Godot-native measurement

`march-native-measure.json` is the certifier's own output for the re-authored GLB
(`march-native-measure.config.json`). It is not a certificate: the pivots run without a provider, so the
small turns fail, and that is the LOCO-CERT-ARCH node's job.

`before-after-measure.json` re-measures, offline, the shipped capture and the re-authored capture with
ONE tool version: the #291 certifier with its final per-foot planting band. Each foot's band is
inherited from the native MARCH it measures; after this PR that is the re-authored clip.
- Before: left 0.54 mm, right 0.5 mm.
- After: 0.5 mm for each foot.

Bounds are contact 28,474 µm and seam 2,373 µm.

| Quantity | Before (shipped) | After |
|---|---:|---:|
| MARCH slide (per vertex) | 512,453 µm | **6,998 µm** (5,117 + 1,881 margin) |
| Penetration | 5,589 µm | 5,589 µm |
| Hover | 5,729 µm | 5,700 µm |
| Seams (loop / MARCH ↔ pivot) | 1 / 842 µm | 1 / 842 µm |
| Envelope | 374 ≤ 932 sim m | 374 ≤ 932 sim m |
| Skin flags introduced | 0 | 0 |

## Real-window review

The foot views are a real Godot window (`archers.tscn` walking at its stride over a ground marked every
0.1 m, fixed side camera, 24 frames per cycle):
- `feet-toe-swing-before-after.png`: phases 0.29–0.46. Before, the swinging right toe scrapes the ground
  line; after, it clears.
- `feet-cycle-before-after.png`: the whole cycle, every second frame.

Godot-native right-toe clearance, from the same capture: the lowest toe vertex rises to 21–39 mm
(model, about 0.4–0.8 world m) over phases 0.36–0.43. It meets the ground only at toe-off (−1.09 mm at
phase 0.295), while the foot is still planted; the per-vertex slide check covers that contact.

`zoom-*-before-after.png` shows a 5×2 file at the game's camera distances: near 300 m, far 2,600 m and the
opening 10,974 m. The renders use the game's FOV 45° and the archer world scale (k = 21.07), six frames
per cycle, before over after. They are a real Godot window but not the map renderer:
`snapshot_screen --march3d` did not select the archer piece in this setup, so no map march was captured.

An independent critic, given only these sheets, `taste.md` and the rubric, found:
- the same walk at every distance (gait, rhythm, posture, bow carriage);
- no introduced defect (no knee or ankle kink, no pop, the planted heel holds its tick);
- no rubric change.

It asked for the toe clearance as a number; that number is above.
