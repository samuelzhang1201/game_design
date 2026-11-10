# LOCO-CERT-TOOL dry run (archers, 2026-11-10)

`archers-dry-run.json` is what the certifier writes for `archers-dry-run.config.json` on the merged
archer assets (`scenes/models/units/archers.tscn`, Godot 4.7.2, 3623 native samples: MARCH,
PIVOT_LEFT, PIVOT_RIGHT and the hold clip STANDBY). It is a **dry run, not a certificate**: plain
native clip playback (no pose provider), stance = the lower sole patch (`lowest:1`), stops admitted
from any MARCH phase, starts at MARCH 0, the hold at any phase, `turn_q 400000` a placeholder, no
policy row installed. Status `FAIL`, `locomotion_certificate null`. Bounds (R-A, k = 21.0719):
contact 28474 µm, seam 2373 µm.

| Quantity | Sampled | Margin | Total | Result |
|---|---:|---:|---:|---|
| Penetration (ground 1.5% of height below the seat) | 0 | 24142 | 24142 µm | pass (margin from STANDBY's motion) |
| Stance hover above the seated plane (lowest patch vertex) | 18706 | 5205 | 23910 µm | pass |
| Slide per stance | 114824 | 5299 | 120123 µm | **fail** (PIVOT_RIGHT at +1 µdeg: the 180° clip played for a tiny turn) |
| Loop seam (last pose before the wrap → phase 0) | 1 | 0 | 1 µm | pass |
| Seam MARCH 0 → pivot 0, pivot 1 → MARCH 0 | 842 | 0 | 842 µm | pass (reproduces #231's 0.841 mm) |
| Seam, stop from any MARCH phase into a pivot | 570285 | 8982 | 579267 µm | **fail** (MARCH 0.171) |
| Seams to and from STANDBY (stop, start, stationary pivot) | up to 2167872 | 28762 | 2196634 µm | **fail** |
| Envelope (STANDBY) | 504 sim m | | ≤ 932 | pass |
| Skin diagnostic (R-B) | 0 introduced | | | pass (native playback introduces none) |
| Stance coverage | every foot stands in every clip | | | pass |

MARCH-only slide with this stance rule is 96.6 mm with forward −Z; +Z gives 1.6 m, which confirms
the axis. Each arm's certificate must supply:

- a pivot provider that maps an arbitrary turn to a contact-preserving pose;
- stop and start phases its consumer actually admits, and transitions to and from the hold clip;
- an authored stance plan in place of `lowest:1`.

The dry run binds the tool by `tool_sha256`. Re-run it after any change to the tool.
