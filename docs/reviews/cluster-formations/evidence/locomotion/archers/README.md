# Archers locomotion certificate (LOCO-CERT-ARCH, 2026-11-27)

The archers draw the longbowman (`tools/units3d/archer_parts/README.md`): the owner's parts Tripo archer on the
infantry's rig contract, `scenes/models/units/archers.tscn`. `certificate.json` certifies that scene with its own
provider, `Map3DArcherLocomotion` (the infantry's solver on this body's plan, `archers_pivot_plan.json`), at the
arm's footprint radius (932 m) and its own scale: k 25.7242 (rest height 1.6433 m at size 0.62), so contact
23325 µm and seam 1944 µm; stride 1.2586 m off its MARCH. Status **NUMERIC_PASS**: penetration 6.9, hover 5.8,
slide 10.7 of 23.3 mm (MARCH 10.7, the pivots 1.4), seam 0.001 of 1.9 mm, envelope 567 m in 932, skin introduced 0.

The first run failed on the pivots at a 1 µ° turn (slide 206 mm): a pivot step's lift scales with the turn but its
travel does not, and the entry (359/420, mid-stride) and the held feet (under the hips) were 20 cm apart. The entry
is now the held frame, 400/420, and the held feet stand where its soles do (`pivot_mapping.py` `PLACE_NATIVE`).

**Consumer requirement**: stop, start and hold only at MARCH phase 400/420, the hold being that MARCH pose; the
pivot pose for any turn from `Map3DArcherLocomotion`.

Real-window review (2026-11-27): MARCH over striped ground and the provider's pivots
(`tools/units3d/royal_install/march_frames.gd` / `pivot_frames.gd --arm archers`), the ATTACK clip, and the map
with a marching archer regiment before/after (`map-before-after.png`, `attack-draw-release.png`, `pivots.png`),
with an independent critic: the new figure preferred; no blocker.
