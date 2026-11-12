# LOCO-ROY-PROVIDER numeric check (royal, 2026-11-13)

`provider-check.json` is what main's certifier (`tools/units3d/certify_locomotion.py`, #291,
tool sha256 `0959a633…`) writes for `provider-check.config.json` on the royal figure posed by
`Map3DRoyalPivot` (`scripts/map3d/map3d_royal_pivot.gd`) through the shared `Map3DPivotProvider`.
It is **a check, not the certificate**. LOCO-CERT-ROY certifies, and no policy row is installed.
Status `FAIL` comes from native MARCH alone (below). Bounds (R-A, k = 20.4518): contact 29338 µm,
seam 2445 µm. 32030 samples over the certifier's dense turn grid (±1 µdeg … ±180°, wraps).

Consumer requirement (coordinator ruling 2026-11-11): stop, start and hold only at MARCH 0.4375
(key 7/16). The pivots leave and rejoin MARCH there, and the hold is MARCH frozen there.

| Quantity | Sampled | Total | Result |
|---|---:|---:|---|
| Slide, PIVOT_LEFT / PIVOT_RIGHT (per vertex, band 0.5 mm per foot) | 5080 / 5077 | 16068 / 16065 µm | pass |
| Hover above the seated plane (witness PIVOT_LEFT −45°) | 500 | 4462 µm | pass |
| Penetration, pivots alone | 0 | ≤ 12936 µm (margin) | pass |
| Seams MARCH(7/16) → pivot(0), pivot(1) → MARCH(7/16), every grid turn | 1 | 1 µm | pass |
| MARCH loop seam | 2269 | 2269 µm | pass |
| Envelope (witness MARCH) | 737 sim m | ≤ 749 | pass, so `unit_footprints.csv` R stays 749 |
| Skin diagnostic (R-B), introduced by the provider | 0 | | pass (55593 inherited) |
| Stance coverage | every hoof stands in every clip | | pass |
| Slide, native MARCH | 329629 | 339795 µm | **fail**, LOCO-CERT-ROY's |
| Penetration, native MARCH (φ 0.734) | 23483 | 36419 µm | **fail**, LOCO-CERT-ROY's |

The horse eases from MARCH to the stand over one hoof step, and the rider (the bones below
`Saddle`) over at least a quarter of the turn. An earlier run that eased the whole body over a
quarter turn introduced 11506 skin flags. All of them were on nine chest and fore-forearm edges,
inside the blend windows.

`provider-review/` holds the real-window frames (`tools/units3d/royal_install/pivot_frames.gd`,
never headless): 90° and 180° sequences, before/after crops of the ease, and a dense 90° strip (k/48) through both ease boundaries, which shows no pop. Independent critic:
nothing blocking. Its notes, all mild:
- a crease at the gaskin around p2/12;
- an elbow stretch around p11/12;
- the blade crossing the helmet line mid-turn, which is the installed STANDBY pose.
