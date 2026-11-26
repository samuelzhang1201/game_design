# Militia locomotion certificate (LOCO-CERT-MIL, 2026-11-26)

The militia (spec `docs/superpowers/specs/2026-11-26-militia-arm-design.md`) draw the militiaman:
`assets/3D/units/army_models.tres` binds the arm to `scenes/models/units/militia.tscn`
(`tools/units3d/militia_arp/README.md`). `certificate.json` certifies that scene with its own
provider, `Map3DMilitiaLocomotion` (the infantry's solver on this body's coupled pivot plan,
`militia_pivot_plan.json`), at the arm's footprint radius (927 m, `data/army/unit_footprints.csv`)
and its own scale: k 24.7922 world m per model m (rest height 1.7051 m at size 0.62), so contact
24202 µm and seam 2017 µm; stride 1.5042 m measured off its MARCH. Status **NUMERIC_PASS**:
penetration 4.3, hover 4.8, slide 17.7 of 24.2 mm (MARCH 16.0, the pivots 7.6), seam 0.001 of 2.0 mm,
envelope 398 m in 927, skin introduced 0.

The first run failed on the installed MARCH, not on the pivots: slide 317 mm. The exporter's foot
lock took a foot's vertices by their heaviest vertex group, and this body carries its parts as
groups too, so the lock saw a fifth of the right shoe; the planted shoe sank 21 mm and the swinging
toe scuffed under the ground. The lock was corrected and MARCH re-exported
(`tools/units3d/militia_arp/README.md`, "MARCH's ground contact"); the stride went from 1.3597 to
1.5042.

The pivot pair's own audit (`tools/units3d/soldier_arp/test_pivot_mapping.py`, fixture
`tests/fixtures/militia_pivot_mapping.json`): skin flags introduced 0, penetration 1 µm, hover
278 µm, slide and seam 1 µm on both turns.

The skirt: its 30 bones hold MARCH's passing frame with the legs through a pivot, and the front
chains swing out over a stepping knee (`pivot_mapping.py` `HELD` / `NUDGE`; the provider keeps those
keys at every turn). `tools/units3d/militia_arp/check_glb.py` prints no leg through the cloth in any
of the twelve installed clips, nor on the provider's poses at 1°, 45°, 135° and 179.999999° either
way.

**Consumer requirement**, as the infantry's (the body walks the same authored stances): stop, start
and hold only at MARCH phase 8/420, the hold being that MARCH pose; the pivot pose for any turn from
`Map3DMilitiaLocomotion`.

Real-window review (2026-11-26): MARCH over striped ground (`tools/units3d/royal_install/march_frames.gd
--arm militia`) and the provider's pivots at 2°, −45°, 90° and 180° (`pivot_frames.gd --arm militia`),
with an independent critic on the pivot sheets: no leg through the cloth, feet on the ground, no
broken pose; it found the hem kicking out to a corner on small turns, after which the neighbouring
chains were given half the swing. Still owed: the same review on the map with a militia REGIMENT
marching and wheeling. No campaign holds one until the spec's step 2, and the candidate locomotion
path that plays these pivots has no ordinary caller yet.
