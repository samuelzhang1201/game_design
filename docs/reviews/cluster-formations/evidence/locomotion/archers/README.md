# Archer locomotion certificate (LOCO-CERT-ARCH, 2026-11-13)

`certificate.json` is the output of main's `tools/units3d/certify_locomotion.py` (per-foot planting band, #291)
for `certificate.config.json`. It runs on main's assets, with the re-authored archer MARCH from #299
(`archers.glb` `f7112ff7…`), and its status is **NUMERIC_PASS**. Its digest (`2f3d0aab…`) binds the tool,
the config and every input: scene, GLB, textures and the provider.

| Quantity | Total (sampled + margin) | Bound |
|---|---:|---:|
| Penetration (rendered ground) | 5589 µm | 28474 µm |
| Stance hover (lowest sole vertex above the seated plane) | 5700 µm | 28474 µm |
| Slide per planted sole vertex, MARCH | 6998 µm | 28474 µm |
| Slide, PIVOT_RIGHT (whole turn grid) | 8958 µm | 28474 µm |
| Slide, PIVOT_LEFT (whole turn grid) | 14499 µm | 28474 µm |
| Slide, pooled | 19558 µm | 28474 µm |
| Seam, every required boundary (loop, stop, start, hold, both pivots, whole turn grid) | ≤ 842 µm | 2373 µm |
| Envelope | 374 simulation m | 932 m |
| Skin (R-B), flags introduced over the native seek | 0 | 0 |

The planting band is inherited from the native MARCH: H is −5.40 mm for the left foot and −1.09 mm for
the right, so both bands are 0.5 mm. The seam's 842 µm is the MARCH-0 ↔ pivot-0 pose step, inherited
from the shipped pivots (the re-author kept frame 1 byte-identical).

**Consumer requirement** (recorded in the certificate): stop, start and hold only at MARCH phase 0,
and the hold is that MARCH pose. This is the phase the archers' pivots enter and leave from. The
certificate binds `turn_q` 400000, the contract's example value; contact does not depend on duration.
A LOCO-POLICY row with another `turn_q` means re-running the certifier.

## Provider

`Map3DArcherLocomotion` (`scripts/map3d/map3d_archer_locomotion.gd`, on `Map3DPivotProvider`) gives the
pose for any committed turn T. Scrubbing the 180° clip for another turn is not certified.

- The installed PIVOT_LEFT/RIGHT (a half turn) plays at the operation phase.
- Each foot's world track is turned about the pivot by (|T|/180° − 1) × that foot's accumulated native
  heading. A planted foot's heading is constant, so it stays planted. Phases 0 and 1 are the native
  endpoints, and T = ±180° is the clip itself.
- A two-bone IK in the leg's own plane reaches the new foot. Bone spans are kept and the pelvis
  (`root.x`) stays native.
- The body above the legs eases toward the entry pose by |T|/180°, so a small turn carries no half-turn
  arm swing.

GUT (`tests/map3d/test_archer_locomotion.gd`) checks five properties:
- a half turn equals the native clip;
- every turn keeps the native endpoints;
- a planted right foot holds the world to within 3 mm for turns of 1 µdeg, 2° and 90°;
- the leg spans and the pelvis are kept, for turns from 1 µdeg to ±90° at four phases;
- a turn on the other clip is refused.

## Real-window review (R-C)

The review followed the `visual-review` skill in a real Forward+/Metal window (1400×1000). The shipped
`archers.tscn` turns in place over a ground marked every 0.1 m, seen from a low oblique camera, eight
frames per turn. Each sheet puts the shipped 180° clip scrubbed for that turn (before) over the provider
(after):
- `turn-2deg-before-after.png`
- `turn-90deg-before-after.png`
- `turn-180deg-before-after.png` (identical by construction)

The sheets are rendered with the final leg IK. Two independent critics saw them, each given only the
sheets, `taste.md` and the rubric.

**First pass.** No taste-principle break, and the provider a clear improvement:
- at 2° the feet step almost in place;
- at 90° they step round about a quarter turn and end uncrossed, where the scrubbed clip crosses
  them.

**Second pass**, after the IK fix. No principle-breaking defect. The provider ranks clearly better at
2° and slightly better at 90°, and 180° reads as the authored turn.

Three points were recorded, none blocking:
- **The far foot is lifted at the 2° endpoints.** This is the MARCH-0 pose the consumer requirement
  holds, and the shipped clip has the same pose.
- **At 90° the far toe sits close behind the near heel (phases 0.57–0.71).** It does so in both rows.
  Measured over 129 phases, the closest distance between the two lower legs' bone axes (knee–ankle
  and ankle–toe, skeleton space) barely changes:

  | Turn | Native | Provider |
  |---|---:|---:|
  | +2° | 299.5 mm | 290.0 mm |
  | +90° | 299.5 mm | 297.9 mm |
  | −90° | 282.8 mm | 282.2 mm |

  The provider brings the legs no closer than the shipped clip does.
- **All sheets are close views.** At playing zoom a turn this small barely shows; the archer's
  map-zoom sheets are in `march-reauthor/`.

The MARCH foot views and map-zoom sheets are in `march-reauthor/` (#299).

## Re-issued for LOCO-POLICY (2026-11-14)

Re-certified on main d61d9756 with the LOCO-POLICY tree: the certifier sha, `data/army/balance.csv` (the new `body_locomotion_*` rows) and, for some arms, other hashed inputs had changed since the first issue. The status is still NUMERIC_PASS and the measured totals and bounds are unchanged; only the digest moved. The installed row is `data/army/unit_locomotion.csv`.
