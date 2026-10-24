# Archer gear: geometry and visual acceptance

Scope: bow, arrow and loaded quiver only. The character GLB (including its
73-bone rig and six clips), body atlases and authored model scene are unchanged
byte-for-byte; `manifest.json` records their hashes. No engine, order routing,
formation settings, camera settings or authored scene/material properties changed.

The installed gear uses 8,130 / 13,310 / 17,863 triangles, 39,303 total versus
287,530 originally (86.33% fewer). Including the unchanged 94,096-triangle body,
the highest-detail equipped figure is 133,399 versus 381,626 triangles. Native
LODs remain enabled; these are base geometry counts, not a claim about actual
per-frame drawing or game-wide FPS.

`near-front.png`, `near-back.png` and `six-clips.png` compare original,
conservative and proposed, left to right. The controlled close view forces base
meshes and samples identical clip times. The conservative props total 55,963
triangles; the proposed candidate is installed. The review must independently
judge silhouette, grips/string, texture seams, material continuity and lost detail.
Implementation inspection found no obvious loss; this does not substitute for
that independent review.

`game-100-overview.png`, `game-100-crop.png` and `game-1000-overview.png` are real
2560×1600 Forward+ window captures through the existing `snapshot_screen`
runner: seed 42, quiet/paused campaign, hold-line fixture, shot frame 90. The
camera frames the first admitted archer figure at 100 or 1000 metres and yaw
120 degrees; its clip is frozen halfway for comparison. No unit positions or
simulation state are altered by camera framing. Background lighting/landscape
remain the actual map. Crops use nearest-neighbour enlargement, not AI enhancement.

Build: `gear_lod.py` and `gear_bake.py`, settings from indexed `archer_gear_lod`.
Surface-constrained isotropic remeshing preserves thin parts; bow-string weights
come from barycentric interpolation on the original surface. New UVs receive
albedo, metal/roughness and tangent-normal bakes through an explicit smooth cage.
Original high-resolution inputs are preserved locally in `/tmp/archer_gear_master`
and recoverable from Git base `55c5ada2becbbc0f94a74c3cc14459d987c49edf`.
The build audit records their SHA256 values. The source and delivered GLBs retain
matching extracted-image names, so fresh imports cannot replace the rebakes with
old UV layouts. Installation retains the existing mesh UIDs and named bind palette.

Verification on final candidate:

- Default decikit gates pass before export and after GLB reimport; no tolerance
  was widened. `build-audit.json` and `roundtrip-audit.json` retain all metrics.
  Canonical inspection welds glTF render seams and interprets exported hard-edge
  normal discontinuities. It preserves delivered winding on intentionally open
  feather surfaces instead of asking a normal recalculation to choose an inside.
- All six original clips are sampled at 11 times each. Bidirectional posed-surface
  p95 distances remain at or below 1.46 mm. The largest sampled distance is
  12.18 mm (GARRISON bow; DRAW bow reaches 11.68 mm); other gear stays below
  4.98 mm. These remain within the existing 6 mm p95 / 20 mm maximum gates;
  `pose-check.json` retains all samples.
  The check applies each body bone's deformation delta, accounting for Blender's
  rest-axis reconstruction of separately imported rigs. Vertex-to-vertex distance
  is unsuitable for stretched triangles; this check measures actual surfaces.
- `./run_tests.sh` on archer, unit-scene, editor-owned-look, data-layout,
  scene-layout and guide-size scripts: 7 scripts, 40 tests passed, 39,644 asserts.
  The new equipment-budget test failed on the original meshes before the build.
- Isolated nine-figure formation, forced base meshes, 2560×1600, 180 frames:
  mean 8.334 → 8.333 ms, p95 8.674 → 8.913 ms. Both runs are capped near
  120 Hz; this establishes no observed material regression, not an FPS gain.
  `formation-bench.json` retains the readings.
- Python compile, shell syntax and `git diff --check` passed. The art-kit generator
  was rerun; archer gear is absent from its contracts, so unrelated regenerated
  specifications were not adopted.

Exact capture/geometry-check scripts are retained as `.txt` records to avoid
Godot importing review evidence as project scripts. They use this implementation
worktree and scratch locations; copy them to `/tmp` and adjust those paths when
reproducing elsewhere. Full-resolution source frames and command logs remain in
`.superpowers/archer-gear-lod/` and `/tmp/unit_detail_review/` in the owned worktree.
No routine full GUT, campaign/balance suite or game-wide performance sweep was run.
Required current-HEAD CI and the sole Review's independent visual acceptance are
still required before merge.
