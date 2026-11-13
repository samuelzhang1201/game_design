# Cavalry locomotion evidence

`march-native-contact.json`, `march-native-reacquired.json` and `march-phase.json` are the
LOCO-CAV-PHASE inputs (the distance-to-phase atlas, see `cavalry-march-contact-prerequisite.md`).

## LOCO-CAV-PROVIDER (2026-11-13): provider check, NOT a certificate

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
