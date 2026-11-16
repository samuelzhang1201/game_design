# CF04c-VISUAL review (2026-11-14)

Real-window acceptance of the candidate consumer (`Map3DCandidateGait` / `Map3DCandidateBodies`, v2
locomotion) with the five installed policies (`data/army/unit_locomotion.csv`, LOCO-POLICY #323).
Fixture: `tools/map3d/body_paths_fixture.gd --v2` (macOS, Metal Forward+, real window, never headless).
Evidence sheets: `evidence/cf04c-visual/`.

## Verdict

**Visual and determinism acceptance passes. FPS accepts every case run (straight legs, the archers'
and infantry's turns), with one open blocker: cavalry and royal pivots.** One provider `solve` costs
19.4 ms (cavalry) and 23.4 ms (royal) per call (archers 1.6, infantry 6.7; headless timing, one
call). The consumer makes one solve per (arm, clip, turn, phase) per frame and shares it across
figures, so a single cavalry or royal pivot frame alone exceeds the high tier's 12 ms budget. Its
fix is in the certified providers (per-turn precomputation of the entry/exit locals and the
expanded contact plan), which voids their certificates: a LOCO-node step, not this one.

## What was run

| Case | Setup | Result |
|---|---|---|
| three-way crossing | infantry W→E, archers E→W, cavalry N→S, 1x, 1500 m and 5000 m, 2560x1600 | moves, no refusal (`crossing-1x.jpg`, `crossing-1500-full.jpg`, `far.jpg`) |
| opposing / L-detour | 1x, 1500 m | no refusal (`opposing-detour-half.jpg`) |
| turn (pivots) | camera following the archers, every pivot frame captured | pivots in place, no slide (`turn.jpg`) |
| pause / 4x | speed 0 and 4 | paused figure geometry identical f0..f199 (`pause.jpg`), 4x clean (`4x.jpg`) |
| half strength | `--fit 500` | no refusal |
| all five arms holding | infantry, archers, cavalry, artillery, royal at 1500 m | each holds its admitted MARCH phase (`arms.jpg`) |
| frame-rate variation | crossing at 4x, `--fps 30` vs uncapped | final `state_hash` identical (1d09940d…) |
| recording | `--write-movie`, 1280x800, 30 fps, 360 frames | local only (78 MB, not committed) |

## Performance (high tier, 3024x1964, budget 12 ms, clock running, `--v2`)

Frame ms (p95 / median). "base" is the same fixture with `--baseline` (ordinary pieces, same
committed state); the means of both include the fixture planning each slice inside a frame.

| Case | near v2 | near base | mid v2 | mid base | far v2 | far base |
|---|---|---|---|---|---|---|
| crossing, still | 8.55 / 8.31 | 8.55 / 8.31 | 11.89 / 11.60 | 11.89 / 11.66 | 8.51 / 8.31 | 8.46 / 8.33 |
| crossing, `--pan` | 9.42 / 8.32 | 8.63 / 8.31 | 22.50 / 11.78 | 21.36 / 11.70 | 12.67 / 9.77 | 12.21 / 8.32 |
| turn, `--pan` | 8.64 / 8.31 | 10.03 / 8.32 | 20.96 / 11.63 | 20.84 / 11.41 | 11.45 / 8.30 | 10.82 / 8.32 |

The panned mid row is over budget for the ordinary pieces too (not introduced here). Before this
step's fixes v2 cost +8 ms median (crossing) and +14 ms (turn); three consumer costs were found and
removed, each output unchanged:

1. `sample_candidate` re-ran the full v2 saved-plan check per unit every frame (~1 ms a unit):
   now remembered by the control's native hash (`Map3DCandidateBodies._loco_saved_ok`).
2. `BodyMotion.sample_locomotion_candidate` re-proved every move's heading per frame (8 ms for one
   diagonal unit): the engine now exposes `sample_locomotion_rows` (the interpolation alone); the
   consumer admits a timeline once per moves hash and only interpolates after.
3. MARCH was posed by play/seek/stop per player per frame: now held on its clip at speed 0 and
   sought (no frame delta, no crossfade); a pivot's provider solve is shared by every figure at one
   (arm, clip, turn, phase).

## Independent critique (fresh agent, sheets + taste.md + rubric only)

No defect found was caused by the consumer. Its findings, with dispositions:

- **Figures stand inside woods and hedges** (should fix): the march grid treats woods as open
  ground; pre-existing on the ordinary path. Follow-up for the terrain/placement owner.
- **Holding figures freeze mid-stride, all on one MARCH frame** (should fix): this is the ruling
  in force (`hold_clip` MARCH only; GARRISON/STANDBY not yet certified). Needs a certified hold
  pose (owner ruling + certifier).
- Artillery stand-in reads as a second infantry; royal horses near-white (pre-existing art).
- Far (5000 m) infantry/archers merge into woods (pre-existing readability).
- Pivot reads as a clean in-place heading change (accepted).
- Its "empty pause/baseline" note was a wrong crop window; re-cropped (`pause.jpg`). The fixture
  does not drive the ordinary path's day walk, so `--baseline` is a performance baseline only.

## Requirements this surfaced for ACT-DRIVER (the production driver)

- **Whole waypoint prefixes.** v2 executes only complete affordable prefixes; a long route
  requested whole holds still. The driver must request, per slice, the longest prefix the row's own
  timeline completes (the fixture's `_commit_v2`).
- **Whole strides.** The consumer refuses a leg that is no whole number of MARCH strides within
  `contact_um` (CF04c-CONSUMER ruling), so the driver stages each leg as whole strides of its arm and
  re-requests a planner-trimmed (collision) prefix as whole strides until every leg runs complete.
- **Column order.** The planner reserves rows rear-first, so a column's rear rows are trimmed to
  stubs behind still-stationary front rows.
- **Facing.** "A final pivot restores row facing": every slice of a march off the row's facing
  pivots out and back. A march needs its row facing written to its heading, or a turn never
  persists.
