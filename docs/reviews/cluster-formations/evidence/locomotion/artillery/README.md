# Artillery locomotion certificate (LOCO-CERT-ART, 2026-11-13)

The artillery has no model of its own yet: `assets/3D/units/army_models.tres` binds it to the
infantry's `scenes/models/units/infantry.tscn`. `certificate.json` is the infantry's provider and
config (`../infantry/`) certified at the artillery's own footprint radius (875 m,
`data/army/unit_footprints.csv`, `cf01/measurements.json`) with the infantry's scale (same model, same `size`),
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
median travel per frame x 35 frames), `exact_pace` 1 and `steps` 0.26;0.77 (the footfall shares, so the halt into
GARRISON lands on a footfall). `exact_pace` also gives each man his own stature
(`Map3DMarchLag.stature`), as it does the infantry's. With the old 1.1 the MARCH slide is not
the certified one.

**Consumer requirement**, as the infantry's: stop, start and hold only at MARCH phase 25/28,
the hold being that MARCH pose; the pivot pose for any turn from `Map3DInfantryLocomotion`.

**Real-window review (R-C):** the pivots and MARCH are the infantry's own clips and provider,
reviewed in `../infantry/README.md` (two critic rounds, no taste-principle break). The artillery
draws the same figure at the same size (`army_art.csv` `size` 0.62 for both); what changes is the
MARCH pace, which now matches the ground, and the per-man stature, both as the infantry's.
`certificate.json`'s `visual_review` field stays PENDING as the infantry's does; the review is
recorded in the READMEs.

## Re-issued for LOCO-POLICY (2026-11-14)

Re-certified on main d61d9756 with the LOCO-POLICY tree: the certifier sha, `data/army/balance.csv` (the new `body_locomotion_*` rows) and, for some arms, other hashed inputs had changed since the first issue. The status is still NUMERIC_PASS and the measured totals and bounds are unchanged; only the digest moved. The installed row is `data/army/unit_locomotion.csv`.

## Re-issued for the short-sword soldier (2026-11-16)

The figure is now the ARP short-sword + round-shield soldier (`docs/superpowers/specs/2026-11-16-infantry-arp-shortsword-design.md`). Re-certified on it:
MARCH `stride_m` 1.618 (was 1.765), k 25.8437 world m per model m, R-A bounds contact 23217 µm /
seam 1935 µm, measured penetration 7469, hover 4330, slide 13604, seam 1 µm, sim envelope 503 m (the MARCH blade leans out, polish 2026-11-17),
0 introduced skin flags: NUMERIC_PASS. The consumer now stops, starts and holds at MARCH 13/14
(0.9285714285714286; the knight's was 25/28), the same passing frame of the walk. The visual review
of the new figure (map and close-up, before/after, independent critic) is recorded in the spec.

## Re-issued for the pack walk and idle (2026-11-18)

Owner 2026-11-17/18: STANDBY is the pack's "idle (4)" and MARCH the pack's "sword and shield walk"
(`docs/superpowers/specs/2026-11-16-infantry-arp-shortsword-design.md`, "March"). The walk's
contacts are authored (`game_export.py` `LOCK`: stances left 0.20-0.86, right 0.90-0.35, soles
grounded, swings clear of 12 mm) and its `stride_m` is the locked sole speed over the loop, 1.4838.
Pivots re-fitted on it: entry = exit = hold at MARCH 8/420 (0.01904761904761905). Measured
penetration 4695, hover 4690, slide 17240, seam 1 µm against contact 23217 / seam 1935 µm, sim
envelope 431 m, 0 introduced skin flags: NUMERIC_PASS. (The first try, the walk's own contacts with
a measured stride of 1.40, slid 289 mm: a mid-swing tap counted as planted, and the stride was 6 %
under the soles' speed.)
