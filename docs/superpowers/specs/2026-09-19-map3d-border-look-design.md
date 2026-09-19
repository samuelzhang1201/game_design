# Borders without curls, and a kingdom border worth looking at — design

Owner 2026-09-19 (overnight, "全部按照你的建议做" — no questions; every call
below is the implementer's recommendation, logged for the owner to reverse):

1. Both the kingdom border and the province seams show a strange small loop
   (小回旋) at many corners. Fix it.
2. The kingdom border as one thin solid black line is ugly. Make it better.

## 1. The curls — cause and fix

Investigation (read-only probe over the default pack, 20 kingdom rings):

| stage | back-tracking vertices (turn > 150°) | local self-crossings |
|---|---:|---:|
| raw pack outline | 0 | 0 |
| after `MapGeometry.smooth_closed_through` (uniform Catmull-Rom) | 58 | 108 |
| after `Map3DBorders.kingdom_lines` (world m, resampled) | 58 | 110 |
| centripetal Catmull-Rom, same steps | 0 | 0 |

The pack's Voronoi outlines are clean; the loops are MADE by the smoothing.
Uniform Catmull-Rom ignores segment length, so a very short edge between long
ones (527 such spots, worst ratio 1417:1) overshoots into a cusp or a closed
loop 24–60 m across — invisible far out, 8–20 screen px close in. The ribbon
(`Map3DBorders._side`) then swaps its sides on the cusp and twists.

Fixes:

- **a. Centripetal Catmull-Rom** (α = 0.5, Barry–Goldman) in
  `smooth_closed_through`, after dropping consecutive points closer than
  `1e-3` px. Still passes through every input point. The 2D border and coasts
  use the same function and are fixed with it. (`smooth_open` is a cubic
  B-spline, which cannot overshoot; it is left alone.)
- **b. One curve per shared border.** Each kingdom smooths its own ring, so
  the two copies of a shared edge part near a three-way junction (24 of 323
  edges, up to 85 m) and read as a thin lens. Pin the tangent at every
  JUNCTION vertex — a vertex where the ring's neighbour kingdom changes, or
  the coast begins — so both rings take the same curve there:
  `smooth_closed_through(pts, steps, pinned: PackedByteArray)`; at a pinned
  vertex the phantom neighbour is the reflection of the other side
  (`p0 := 2·p1 − p2`), which makes the curve leave the junction along its own
  edge. `MapOwnership` supplies the pins (`outline_pins`).
- **c. Seams as chains.** `seam_lines` hands 2,132 two-point strips; their
  flat caps overlap at the 1,712 joints (a darker knot at half opacity) and
  every dash restarts. Chain the segments through degree-2 joints into one
  polyline per seam before resampling.
- **d. `_side` keeps its side at a cusp**: when the two directions nearly
  cancel (dot < −0.9), reuse the previous point's side instead of the chord.

## 2. The look (recommendation)

A historical atlas border, readable on the satellite ground, in three
ribbons drawn by the existing `border_line.gdshader` (every value data):

1. **Realm band** — inside each kingdom's outline, a band in the kingdom's own
   colour (`MapPalette.color_of`), `map3d_border_band_px` 9 screen px wide,
   `map3d_border_band_alpha` 0.55 at the line fading to 0 inward. It is what
   tells the two sides of a border apart at a glance (the chequer of the 2D map
   did this with ink alone). One-sided ribbons: `ribbon_arrays(..., one_sided)`
   puts the line's own vertex at offset 0 and the inner one at the full width,
   inward by the ring's winding; the shader's new `fade_across` fades alpha
   along UV.y.
2. **Halo** — a pale parchment line under the ink, `map3d_border_halo`
   `#EFE6D2` at `map3d_border_halo_alpha` 0.7, `map3d_border_halo_px` 3.6, soft
   edge, so the ink reads on dark forest and bright snow alike.
3. **Ink** — the line itself, a warm dark brown `#2A1E16` (`map3d_border`, was
   `#141414`), `map3d_border_width_px` 1.8. Solid.

Seams stay dashed in the ink at half opacity (they are now continuous chains).
The hover outline stays the ink, wider. Final values come from the
visual-review loop (far / mid / near shots, an independent critic); the owner
can reverse any of it by data.

## 3. Testing

- `tests/engine/test_map_geometry.gd`: a synthetic ring with one 0.05-long edge
  between 10-long edges — no local self-crossing, no turn > 150°, every input
  point still on the curve; a pinned vertex leaves along its own edge.
- `tests/map3d/test_map3d_borders.gd`: over the default pack, `kingdom_lines`
  has no local self-crossing and no back-tracking vertex; both copies of every
  shared kingdom edge within 1 m of each other at the junctions; `seam_lines`
  returns chains (fewer lines than segments, every chain continuous); a
  one-sided ribbon's inner vertices lie inside the ring; no ribbon side swap
  between neighbouring points.
- Visual: the visual-review loop, and `tools/map3d/bench.gd` within budget
  (three extra ribbons are one mesh each).
