# Axemen locomotion certificate (LOCO-CERT-AXE, 2026-11-23)

The axemen (spec `docs/superpowers/specs/2026-11-18-axemen-arm-design.md`, step 4) draw their own
hand-axe soldier: `assets/3D/units/army_models.tres` binds them to `scenes/models/units/axemen.tscn`
(`tools/units3d/infantry_arp/README.md`, "The axemen"). `certificate.json` certifies that scene with
its own provider, `Map3DAxemenLocomotion` (the infantry's solver on this body's coupled pivot plan,
`axemen_pivot_plan.json`), at the arm's footprint radius (927 m, `data/army/unit_footprints.csv`) and
the infantry's scale (the same body: k 25.8437, contact 23217 µm, seam 1935 µm); stride 1.4838 m
measured off its MARCH. Status **NUMERIC_PASS**: penetration 4.7, hover 4.7, slide 17.2 of 23.2 mm,
seam 0.001 of 1.9 mm, envelope 431 m in 927, skin introduced 0.

The pivot pair's own audit (`tools/units3d/soldier_arp/test_pivot_mapping.py`, fixture
`tests/fixtures/axemen_pivot_mapping.json`): skin flags introduced 0, penetration 27 µm, hover,
slide and seam 1 µm on both turns (the infantry's figures).

**Consumer requirement**, as the infantry's (the body walks the same pack walk): stop, start and
hold only at MARCH phase 8/420, the hold being that MARCH pose; the pivot pose for any turn from
`Map3DAxemenLocomotion`.
