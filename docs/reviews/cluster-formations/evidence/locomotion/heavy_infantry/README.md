# Heavy infantry locomotion certificate (LOCO-CERT-HVY, 2026-11-20)

The heavy infantry (spec `docs/superpowers/specs/2026-11-20-heavy-infantry-arm-design.md`, step 3)
draw their own plate soldier: `assets/3D/units/army_models.tres` binds them to
`scenes/models/units/heavy_infantry.tscn` (`tools/units3d/infantry_arp/README.md`, "Another body").
`certificate.json` certifies that scene with its own provider, `Map3DHeavyInfantryLocomotion` (the
infantry's solver on this body's coupled pivot plan, `heavy_infantry_pivot_plan.json`), at the arm's
footprint radius (`data/army/unit_footprints.csv`) and its own scale: k 26.4330 world m per model m
(rest height 1.5992 m at size 0.62), so contact 22699 µm and seam 1892 µm; stride 1.473 m measured
off its MARCH. Status **NUMERIC_PASS**.

The pivot pair's own audit (`tools/units3d/soldier_arp/test_pivot_mapping.py`, fixture
`tests/fixtures/heavy_infantry_pivot_mapping.json`): skin flags introduced 0, penetration 1 µm,
hover 593 µm, slide and seam 1 µm on both turns.

**Consumer requirement**, as the infantry's (the body walks the same pack walk): stop, start and
hold only at MARCH phase 8/420, the hold being that MARCH pose; the pivot pose for any turn from
`Map3DHeavyInfantryLocomotion`.

The real-window review of R-C (the figure marching and turning on the map) is still to do.
