# Axemen locomotion certificate (LOCO-CERT-AXE, 2026-11-18)

The axemen (spec `docs/superpowers/specs/2026-11-18-axemen-arm-design.md`) have no model of their
own yet: `assets/3D/units/army_models.tres` binds them to the infantry's
`scenes/models/units/infantry.tscn`. `certificate.json` is the infantry's provider and config
(`../infantry/`) certified for the arm `axemen` at its footprint radius (927 m, the infantry's,
`data/army/unit_footprints.csv`) with the infantry's scale, status **NUMERIC_PASS**, the same
totals as the infantry's. Installing the hand-axe soldier voids it.

**Consumer requirement**, as the infantry's: stop, start and hold only at MARCH phase 8/420, the
hold being that MARCH pose; the pivot pose for any turn from `Map3DInfantryLocomotion`.
