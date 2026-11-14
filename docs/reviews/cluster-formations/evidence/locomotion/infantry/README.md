# Infantry locomotion certificate (LOCO-CERT-INF, 2026-11-13)

`certificate.json` is what `tools/units3d/certify_locomotion.py` writes for
`certificate.config.json` on main's certifier (the per-foot planting band, #291) plus this PR's
dependency-closure fix (a `res://` path ending a comment's sentence), status
**NUMERIC_PASS**; its digest binds the tool, the config and all 19 inputs (scene, clips, the
provider, its plan, the helper). The artillery uses the same model and is certified separately
at its own radius (LOCO-CERT-ART).

| Quantity | Total (sampled + margin) | Bound |
|---|---:|---:|
| Penetration (rendered ground) | 7509 µm | 22769 µm |
| Stance hover (lowest sole vertex above the seated plane) | 5995 µm | 22769 µm |
| Slide per planted sole vertex | 19506 µm | 22769 µm |
| Seam, every required boundary (loop, stop, start, hold, both pivots, whole turn grid) | ≤ 1 µm | 1898 µm |
| Envelope | 477 simulation m | 927 m |
| Skin (R-B), flags introduced over the native seek | 0 | 0 |

Planting band (inherited from the shipped native MARCH): left foot H 2.256 mm, band 2.756 mm;
right foot H −1.843 mm, band 0.5 mm. The slide maximum is a near-zero turn (+2°) whose swing
foot barely lifts and shuffles inside the left band; the hover maximum is native MARCH itself.

**Consumer requirement** (owner ruling A, recorded in the certificate): stop, start and hold only
at MARCH phase 25/28, the hold being that MARCH pose; GARRISON / STANDBY holds are not admitted
until certified separately. The certificate binds `turn_q` 400000 (the contract's example; contact
does not depend on duration): a LOCO-POLICY row with another `turn_q` means re-running it. The pose for any turn comes from `Map3DInfantryLocomotion` through
`Map3DPivotProvider`; scrubbing the 90° clip for another turn is not certified.

## Real-window review (R-C)

`visual-review` skill, real Forward+/Metal window 2560x1600, the shipped `infantry.tscn` at the
closest-zoom figure size (about 800 px), turns +1 µdeg, +45, +90, +180 and −2°, front and side,
body and feet crops; an independent critic per round.

1. Round 1 found the 90° clip's MARCH arm swing playing for a near-zero turn (a flourish with no
   turn). The provider now scales the body above the legs by |turn| / 90° toward the held entry
   pose (±90 unchanged).
2. Round 2: no taste-principle break; no row worse than the shipped +90. Ranking
   +45 ≥ +90 > +180 > +1 µdeg ≈ −2°. Recorded, not blocking: near-zero turns still mark time
   in place (needed: the entry/exit MARCH pose has the left foot in swing); the +180 shield
   sweep is theatrical but clear of the body; the sword point comes near the forward boot.

## Re-issued for LOCO-POLICY (2026-11-14)

Re-certified on main d61d9756 with the LOCO-POLICY tree: the certifier sha, `data/army/balance.csv` (the new `body_locomotion_*` rows) and, for some arms, other hashed inputs had changed since the first issue. The status is still NUMERIC_PASS and the measured totals and bounds are unchanged; only the digest moved. The installed row is `data/army/unit_locomotion.csv`.
