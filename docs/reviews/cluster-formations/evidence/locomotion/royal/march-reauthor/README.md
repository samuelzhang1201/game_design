# LOCO-ROY-MARCH: the re-keyed royal MARCH (owner ruling R-J, 2026-11-13)

The owner ruled "Re-author royal MARCH" after main's certifier measured the delivered gallop's native
MARCH at slide 339,795 µm and penetration 36,419 µm. Both bounds are contact 29,338 µm. The method is
in `tools/units3d/royal_install/README.md` ("The re-keyed MARCH"). In short:

- the four hoof chains are re-keyed at 64 intervals, so every planted hoof holds the ground and rolls
  over its own heel and toe;
- the stride is the clip's own measured value;
- the pivots' admitted phase (MARCH 0.4375) keeps the delivered pose;
- nothing else changes.

| File | What |
|---|---|
| `march-keys.json` | `march_reauthor.gd`'s output, the transplant's input: per hoof-chain bone, the re-keyed and the native rotation at each of the 65 key times, plus the solve's report |
| `march-measure.config.json` | the certifier config: `provider-check.config.json` (`../`) with `stride_m` 3.3122, `army_art.csv`'s |
| `march-measure.json` | main's certifier (`tools/units3d/certify_locomotion.py`) on the re-keyed clip with `Map3DRoyalPivot` posing the pivots |

`march-measure.json` is **a measurement, not the certificate**: LOCO-CERT-ROY certifies, and no
policy row is installed. It reads NUMERIC_PASS. The bounds (R-A, k = 20.4518) are contact 29,338 µm
and seam 2,445 µm.

| Quantity | Delivered MARCH (`../provider-check.json`) | Re-keyed |
|---|---:|---:|
| Slide, native MARCH (per vertex, 0.5 mm bands) | 339,795 µm | **23,104 µm** (12,117 sampled + margin) |
| Penetration (all clips; witness) | 36,419 µm (MARCH 0.734) | **12,936 µm** (0 sampled; margin only) |
| Hover | 4,462 µm | 3,629 µm |
| Seams (MARCH loop; MARCH 7/16 ↔ pivots, every grid turn) | 2,269 / 1 µm | 367 / 1 µm |
| Envelope | 737 ≤ 749 sim m | 737 ≤ 749 sim m (R stays 749) |
| Skin (R-B), introduced | 0 | 0 |
| Planting bands H (fl, fr, hl, hr) | −11.8, −59.5, −19.1, −3.3 mm | −4.2, −0.6, −0.7, −2.3 mm (every band 0.5 mm) |

**Stride.** `army_art.csv` royal `stride_m` drops from 5.5 to 3.3122. The 5.5 came from a 2.25 m
"gallop stride" (the front hooves' stance speed) times a factor tuned on other arms. 3.3122 is the
least-squares ground speed of the clip's own planted soles, so the piece now gallops at a higher
cadence over the same ground.

**What was tried, and why the method is as it is.** Each run is main's certifier on the
transplanted clip.

- **128 keys with the import at 240 fps** passed every MARCH number. It failed
  `test_royal_boundary_input`: the native-jets proof needs keys at least 5.12 ms apart, because Godot
  treats 1e-5 s before a key as that key. At 120 fps the 64 keys are 8.3 ms apart.
- **Holding a hoof flat through its whole native stance** is unreachable: its break-over rolls up to
  82°. The stance therefore ends where the toe is deepest.
- **16 keys at 30 fps** (the delivered key times) failed slide (427 mm), hover (65 mm) and skin
  (502 introduced). The coarser keys put the stance ends at different keys, so the rank of the two
  lowest hooves changes. A swinging hind hoof then counts as a stance in the certifier's
  planting-band rule, and its band grows to 58 mm.
- **Rolling about the sole patch's front edge** drove the hoof wall 64 mm under the plane. Seating
  and pivoting on the whole hull fixed it.
- **A swing starting at the native velocity** slid the lifting toe 38 mm. The first and last three
  swing keys now blend from the planted motion.
- **Moving the pivots' entry pose** flipped the R-B rule on two chest/fore-forearm edges whose pivot
  stretch sits within 0.4 mm of 4× their entry length (858, then 16, then 780 flags introduced). With
  the entry pose exactly the delivered one: 0.

`../provider-check.json` (LOCO-ROY-PROVIDER) measured the delivered clip and stays as that record.

**Real-window review.** See the PR.
