# LOCO-CERT-TOOL dry run (archers, 2026-11-10)

`archers-dry-run.json` is the certifier's output for `archers-dry-run.config.json` on the merged
archer assets (`scenes/models/units/archers.tscn`, Godot 4.7.2, 2498 native samples). It is a
**dry run, not a certificate**: plain native clip playback (no pose provider), stance = the lower
sole patch (`lowest:1`), `turn_q 400000` a placeholder, no policy row installed. Status `FAIL`,
`locomotion_certificate null`. Bounds (R-A, k = 21.0719): contact 28474 µm, seam 2373 µm.

| Quantity | Sampled | Margin | Total | Result |
|---|---:|---:|---:|---|
| Penetration (ground 1.5% of height below the seat) | 0 | 5589 | 5589 µm | pass |
| Stance hover above the seated plane | 18706 | 5205 | 23910 µm | pass |
| Slide per stance | 114824 | 5299 | 120123 µm | **fail** (PIVOT_RIGHT at +1 microdegree: the 180° clip played for a tiny turn) |
| Seam MARCH 0 ↔ pivot ends, loop seam | 842 / 0 | 0 | 842 µm | pass (reproduces #231's 0.841 mm) |
| Seam, cut from any MARCH phase | 570285 | 8982 | 579267 µm | **fail** (MARCH 0.171 ↔ pivot 0) |
| Envelope (bow at MARCH 0.2) | 374 sim m | | ≤ 932 | pass |
| Skin diagnostic (R-B) | 0 introduced | | | pass (native playback introduces none) |

MARCH-only slide with this stance rule is 96.6 mm (forward −Z; +Z gives 1.6 m, so the axis is
right). What the arm's own certificate must supply: a pivot provider that maps an arbitrary turn
(and the MARCH entry/exit phase it admits) to a contact-preserving pose, or a config that admits
only the entry phases its consumer uses, and an authored stance plan in place of `lowest:1`.
The dry run binds the tool by `tool_sha256`; re-run it after any change to the tool.
