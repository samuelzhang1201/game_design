# Cavalry locomotion evidence

## Certificate (LOCO-CERT-CAV, 2026-11-13)

`certificate.json` is main's `tools/units3d/certify_locomotion.py` run on `certificate.config.json`
against main's assets: the re-authored cavalry MARCH (#316, ruling R-I; `cavalry.glb` `0dac618d…`) and
the provider `Map3DCavalryLocomotion` (#314). Status **NUMERIC_PASS**, digest `56b1c287…`. The digest
binds the tool, the config and every input (scene, GLB, textures, provider, pivot plan, data).

| Quantity | Total (sampled + margin) | Bound |
|---|---:|---:|
| Penetration (rendered ground) | 7693 µm | 29273 µm |
| Stance hover | 3627 µm | 29273 µm |
| Slide per planted sole vertex, MARCH | 10902 µm | 29273 µm |
| Slide, PIVOT_LEFT (whole turn grid) | 16549 µm | 29273 µm |
| Slide, PIVOT_RIGHT (whole turn grid) | 15051 µm | 29273 µm |
| Slide, pooled | 17149 µm | 29273 µm |
| Seam, every required boundary (loop, stop, start, hold, both pivots, whole turn grid) | 1 µm | 2440 µm |
| Envelope | 740 simulation m | 804 m |
| Skin (R-B), flags introduced over the native seek | 0 | 0 |

- **Planting band**, inherited from native MARCH: H is −5.85 / −8.54 / −7.97 / −0.75 mm (fore left, fore
  right, hind left, hind right), so every band is 0.5 mm.
- **Pace:** `stride_m` 2.4 is army_art.csv's cavalry row; MARCH needs no phase map.
- **Consumer requirement** (recorded in the certificate): stop, start and hold only at MARCH 7/16
  (0.4375), and the hold is that MARCH pose. The pivots leave and rejoin MARCH there.
- **`turn_q`:** the certificate binds 400000, the contract's example value; contact does not depend on
  duration. A LOCO-POLICY row with another `turn_q` means re-running the certifier.

### Real-window review (R-C)

`certificate-review/`: `tools/units3d/royal_install/pivot_frames.gd --arm cavalry` in a real
Forward+/Metal window at 1200x900, frames 0..12 of +90°, −45°, +180° and +1 µdeg. Each sheet puts the
provider on the pre-#316 MARCH (before, top) over the same provider on the certified MARCH (after,
bottom). `*_feet.png` crop the hooves; `provider_90000000_body.png` shows whole frames 0, 6 and 12.
The independent critic's findings are in the PR.

`march-native-contact.json`, `march-native-reacquired.json` and `march-phase.json` are the
LOCO-CAV-PHASE inputs (the distance-to-phase atlas, see `cavalry-march-contact-prerequisite.md`).

## LOCO-CAV-PROVIDER (2026-11-13): provider check, NOT a certificate (superseded by the certificate above)

`provider-check.json` is `tools/units3d/certify_locomotion.py` on `provider-check.config.json`
(the per-vertex planting band of #291; provider `Map3DCavalryLocomotion`; pivots leave and rejoin
MARCH at 7/16, the hold is MARCH frozen there). Bounds: contact 29273 µm, seam 2440 µm (k 20.4973).

| | total (sampled + margin) | |
|---|---:|---|
| slide PIVOT_LEFT / PIVOT_RIGHT, per planted vertex | 14472 / 15017 µm | pass |
| seams, every required boundary over the whole turn grid | 1 µm | pass |
| hover | 4037 µm | pass |
| penetration (witness PIVOT_LEFT phase 0 = MARCH 7/16) | 7971 µm | pass |
| envelope | 740 sim m ≤ 804 | pass |
| skin (R-B), introduced | 0 | pass |
| stance coverage | | pass |

Overall status `FAIL` is native MARCH alone: slide 90.7 mm with the installed phase map (#302,
applied by the certifier since #311; 79.7 mm at the constant `stride_m`). No phase map can pass it
under the per-vertex band (sampled floor about 29.0 mm before margin): that is LOCO-CAV-MARCH
(#316, owner ruling R-I), which re-keys MARCH; this check is re-run once it lands. No policy row is installed.

Why 7/16: at 8/16 (three hooves down) the left hind is 151 mm up and flexed; its swing to the
seated stand dragged the toe through the 0.5 mm band (pivot slide 196 mm). At 7/16 the right
fore and left hind are only 4.5 and 10.8 mm up, so their first and last steps are short and flat.

## Real-window review

`provider-review/`: `tools/units3d/royal_install/pivot_frames.gd --arm cavalry` at 1200x900,
frames 0..12 of +90 (body, and feet), +180 feet, +1 µdeg, and the installed clip at +90 for
comparison; independent critic (sheets and `taste.md` only), see the PR.
