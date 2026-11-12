# Artillery locomotion certificate (LOCO-CERT-ART, 2026-11-13)

The artillery has no model of its own yet: `assets/3D/units/army_models.tres` binds it to the
infantry's `scenes/models/units/infantry.tscn`. `certificate.json` is the infantry's provider and
config (`../infantry/`) certified at the artillery's own footprint radius (875 m,
`data/army/unit_footprints.csv`) and scale (`docs/reviews/cluster-formations/evidence/cf01/measurements.json`),
status **NUMERIC_PASS**. Any real gun model voids it.

| Quantity | Total (sampled + margin) | Bound |
|---|---:|---:|
| Penetration | 7509 µm | 22769 µm |
| Stance hover | 5995 µm | 22769 µm |
| Slide per planted sole vertex | 19506 µm | 22769 µm |
| Seams (loop, stop, start, hold, both pivots, every grid turn) | ≤ 1 µm | 1898 µm |
| Envelope | 477 simulation m | 875 m |
| Skin, introduced flags | 0 | 0 |

**Data change:** `data/screens/map3d/army_art.csv`'s artillery row still carried the retired
spearman's `stride_m` 1.1 with `exact_pace` 0, while its figure plays the infantry's MARCH. Stride
is measured off the clip, never tuned (`tools/CLAUDE.md`), so the row now takes the infantry's
measurement of that same clip: `stride_m` 1.765 (`game_export._march_measure`, the planted foot's
median travel per frame x 35 frames) and `exact_pace` 1. With the old 1.1 the MARCH slide is not
the certified one.

**Consumer requirement**, as the infantry's: stop, start and hold only at MARCH phase 25/28,
the hold being that MARCH pose; the pivot pose for any turn from `Map3DInfantryLocomotion`.

**Real-window review (R-C):** the pivots and MARCH are the infantry's own clips and provider,
reviewed in `../infantry/README.md` (two critic rounds, no taste-principle break). The artillery
draws the same figure at the same size (`army_art.csv` `size` 0.62 for both); what changes is the
MARCH pace, which now matches the ground as the infantry's does.
