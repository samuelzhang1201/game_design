# Royal locomotion certificate (LOCO-CERT-ROY, 2026-11-14)

`certificate.json` is what main's certifier (`tools/units3d/certify_locomotion.py`, tool sha256 `efc58b66…`)
writes for `certificate.config.json`. Status: **NUMERIC_PASS**. Certificate digest `639941a1…`. It
binds the tool, the config and all 24 inputs:
- the scene and `royal.glb` with its re-keyed MARCH (LOCO-ROY-MARCH, owner ruling R-J);
- the provider `Map3DRoyalPivot`, its plan and its helpers;
- `army_art.csv`, `unit_footprints.csv` and the balance tables.

No policy row is installed (LOCO-POLICY). The certifier sampled 32,410 poses: dense MARCH, and both
pivots over the whole turn grid (±1 µdeg … ±180°, with wraps). Bounds (R-A, k = 20.4518): contact
29,338 µm, seam 2,445 µm.

| Quantity | Total (sampled + margin) | Bound |
|---|---:|---:|
| Penetration (rendered ground) | 12,936 µm (0 sampled) | 29,338 µm |
| Stance hover | 3,629 µm | 29,338 µm |
| Slide per planted sole vertex | 23,104 µm (12,117 sampled; MARCH, fore-left at phase 0.27) | 29,338 µm |
| Seams (loop, stop, start, hold, both pivots, every grid turn) | ≤ 367 µm | 2,445 µm |
| Envelope | 737 simulation m | 749 m (R unchanged) |
| Skin (R-B), flags introduced over the native seek | 0 | 0 |

**Planting band**, inherited from the shipped MARCH, i.e. the re-keyed one. H is −4.2 mm (fl),
−0.6 mm (fr), −0.7 mm (hl) and −2.3 mm (hr), so every band is 0.5 mm.

**Consumer requirement**, recorded in the certificate (coordinator ruling 2026-11-11): stop, start
and hold only at MARCH phase 0.4375 (7/16), the hold being that MARCH pose. GARRISON and STANDBY
holds are not admitted until they are certified separately.

The certificate binds `turn_q` 400000, the contract's example value: a LOCO-POLICY row with another
`turn_q` means re-running it. The pose for any turn comes from `Map3DRoyalPivot` through
`Map3DPivotProvider`; the installed PIVOT clips (STANDBY → STANDBY) are never played. MARCH is
paced by `army_art.csv` `stride_m` 3.3122, the clip's own stride.

## Real-window review (R-C)

`certificate.json`'s `visual_review` field stays PENDING, as the infantry's and artillery's do; the
review is recorded here.

- **MARCH:** reviewed in LOCO-ROY-MARCH (`march-reauthor/README.md`, `march-reauthor/review/`). An
  independent critic found nothing blocking: the planted hooves hold the stripes, and it is the same
  gallop.
- **Pivots:** reviewed in LOCO-ROY-PROVIDER (`provider-review/`, below). An independent critic found
  nothing blocking. A pivot pose is a function of MARCH(0.4375) and the seated stand only, and the
  re-keyed MARCH keeps that pose exactly (`march-keys.json` `admitted_phase_pose_native`; the
  re-keying tool fails otherwise). So those frames are this certificate's pivots.
- **Not judged here:** pace on the live map (pause, 1x, 4x) belongs to CF04c-VISUAL.

---

## LOCO-ROY-PROVIDER numeric check (the delivered MARCH, 2026-11-13)

`provider-check.json` is what main's certifier (`tools/units3d/certify_locomotion.py`, #291 + #311,
tool sha256 `efc58b66…`) writes for `provider-check.config.json` on the royal figure posed by
`Map3DRoyalPivot` (`scripts/map3d/map3d_royal_pivot.gd`) through the shared `Map3DPivotProvider`.
It is **a check, not the certificate**. LOCO-CERT-ROY certifies, and no policy row is installed.
Status `FAIL` comes from native MARCH alone (below). Bounds (R-A, k = 20.4518): contact 29338 µm,
seam 2445 µm. 32030 samples over the certifier's dense turn grid (±1 µdeg … ±180°, wraps).
Since the recording, #310 changed only `army_art.csv`'s artillery row, so the bound sha256 of
that file is stale and the royal row it reads is unchanged; LOCO-CERT-ROY re-runs on the final inputs.

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
