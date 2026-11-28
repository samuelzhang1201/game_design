# Cavalry locomotion evidence

## Two in-place strikes (2026-11-28): certificate re-issued

`cavalry.glb` gained ATTACK_CLEAVE and ATTACK_ARC (and GARRISON's lowered guard); MARCH and the PIVOT
pair are the same source frames through the same export. `certificate.json` is re-issued on the new
GLB, its import, `army_art.csv` (the cavalry `chains`) and the cf01 measurements: status
**NUMERIC_PASS**, digest `5252a604…`, the same bounds (contact 32990 µm) and footprint radius (804 m). Every other
arm's certificate is re-issued for the same hashed inputs with a report equal to the one it replaces.

## The heavy knight (2026-11-21): certificate re-issued on the new figure

The cavalry piece is now the ARP heavy knight on the armoured horse
(`docs/superpowers/specs/2026-11-21-cavalry-heavy-knight-design.md`, `tools/units3d/cavalry_arp/`).
`certificate.json` is `certify_locomotion.py` on the updated `certificate.config.json`: MARCH is the
run (13 frames keyed 8 a frame, each hoof's stance locked on the ground), stride 2.4224, entry = exit =
hold at MARCH 63/104 (left hind and right fore planted), the provider's stand seated from that held
pose (`cavalry_pivot_plan.json` `stand_clip`). Status **NUMERIC_PASS**, digest `f22b7e81…`; k 18.1876,
bounds contact 32,990 µm, seam 2,750 µm. Totals: slide MARCH 16,683 / PIVOT_LEFT 25,546 / PIVOT_RIGHT
25,819 µm, hover 9,902, penetration 25,127, seams 1 µm, envelope 733 ≤ 804 sim m, 0 introduced skin
flags. Planting band H: -1.61 / -2.72 / -0.08 / -0.41 mm (fl, fr, hl, hr).

`certificate-review/heavy_knight_<turn>.png`: `tools/units3d/royal_install/pivot_frames.gd --arm
cavalry` in a real Forward+/Metal window, frames 0..12 (every second shown) of +90°, -45°, +180° and
+1 µdeg on the new figure; they replace the old knight's sheets. The sections below are the old Tripo
knight's history.

## Certificate (LOCO-CERT-CAV, 2026-11-13)

`certificate.json` is main's `tools/units3d/certify_locomotion.py` run on `certificate.config.json`
against main's assets: the re-authored cavalry MARCH (#316, ruling R-I; `cavalry.glb` `0dac618d…`) and
the provider `Map3DCavalryLocomotion` (#314). Status **NUMERIC_PASS**, digest `90e7f594…` (re-issued by LOCO-CAV-SOLVE-PERF, below). The digest
binds the tool, the config and every input (scene, GLB, textures, provider, pivot plan, data).

**Re-issue (LOCO-CAV-SOLVE-PERF, 2026-11-17).** The provider now prepares each turn once and the
shared IK runs on packed arrays, so a warm `solve` costs about 3.4 ms instead of about 10.9 ms
(`tools/units3d/bench_pivot_solve.gd`, 128 phases, median, same machine back to back). The poses are
byte-identical: the re-issued certificate's report equals the previous one exactly, and its 470 MB
capture differs from the previous capture only in the capturing process id. Binding and preparing now
seek STANDBY and MARCH from the rest pose (and MARCH after the turn's PIVOT clip, as `Provider.apply`
seeks it): those clips key only some channels, and main's `solve` let the rest carry over from the
pose the figure showed before (18 leg bones differed in `pivot_frames.gd`'s frame sequence). The
certifier always seeked the PIVOT clip first, so the certified pose is the one now produced from any start. Only the input digests
moved (the provider, `map3d_cavalry_pivot.gd`, `map3d_cavalry_pivot_math.gd`, and main's
`data/screens/map3d/balance.csv`).

`solve-perf/`: `bench.txt` (two back-to-back rounds, main = `wtbase`, this change = `wtperf`; measured
before the rest-pose seek, which only touches a turn's first call), and real-window +90° frames of
`pivot_frames.gd` on main over this change (`turn90_feet.png`, `turn90_body.png`,
`frame01_main_branch_diffx8.png`). They differ only in frames 1, 2, 11 and 12 (at most 605 pixels, single
pixels up to 120 levels): main's frames carry the previous frame's pose in MARCH's unkeyed channels.

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
`certificate.json`'s `visual_review` field stays PENDING, as the tool writes it; this section is the
R-C review.

An independent critic, given only the sheets, `taste.md` and the rubric, found no defect that breaks a
principle: no hoof sinks, slides or pops, and no legs pass through each other. +90° is near identical, with
a slightly longer hind stride in "after"; −45°, +180° and +1 µdeg cannot be told apart, and +1 µdeg holds
one pose over all 13 frames. One point, not blocking: at +90° and +180° frame 12 a hind hoof is in
the air. That is the MARCH 7/16 pose the turn rejoins, so the gait carries on from it (seam 1 µm).
The shield's back face and a seam on the horse's neck by the reins show in both rows and are not
part of this step.

The provider's GUT is `tests/map3d/test_cavalry_locomotion.gd` (#314); it passes on the certified MARCH.

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

## Provider-check real-window review

`provider-review/`: `tools/units3d/royal_install/pivot_frames.gd --arm cavalry` at 1200x900,
frames 0..12 of +90 (body, and feet), +180 feet, +1 µdeg, and the installed clip at +90 for
comparison; independent critic (sheets and `taste.md` only), see the PR.

## Re-issued for LOCO-POLICY (2026-11-14)

Re-certified on main d61d9756 with the LOCO-POLICY tree: the certifier sha, `data/army/balance.csv` (the new `body_locomotion_*` rows) and, for some arms, other hashed inputs had changed since the first issue. The status is still NUMERIC_PASS and the measured totals and bounds are unchanged; only the digest moved. The installed row is `data/army/unit_locomotion.csv`.

## Re-issued for the short-sword infantry (2026-11-16)

Only hashed inputs moved (`army_art.csv`, `data/army/balance.csv` and the cf01 `measurements.json`, for the new infantry figure); this arm measures as before (NUMERIC_PASS, same totals and bounds), only the digest moved.

## Re-issued for the infantry's pack walk (2026-11-18)

Only hashed inputs moved (`army_art.csv` and the cf01 `measurements.json`, for the infantry's new
walk and idle); this arm measures as before (NUMERIC_PASS, same totals and bounds), only the digest moved.
